# credo:disable-for-this-file Credo.Check.Refactor.FunctionArity
defmodule Ectomancer.Prompt do
  @moduledoc """
  Prompt DSL for defining MCP prompt templates.

  Prompts are reusable templates that generate messages based on provided
  arguments. They enable structured, parameterized interactions with LLM clients.

  ## Examples

      defmodule MyApp.MCP do
        use Ectomancer, name: "my-app", version: "1.0.0"

        prompt :analyze_churn do
          description "Analyze user churn over a time period"
          argument :days, :integer, required: true, description: "Days to look back"
          argument :threshold, :float, default: 0.05, description: "Churn threshold"

          messages fn args ->
            [
              %{
                role: "user",
                content: %{
                  type: "text",
                  text: "Using the list_users tool, analyze churn over the last \#{args.days} days with threshold \#{args.threshold}..."
                }
              }
            ]
          end
        end

        prompt :summarize_reports do
          description "Summarize recent reports"
          argument :report_type, :string, required: true,
                    description: "Type of report",
                    enum: ["sales", "inventory", "employee"]

          messages fn args ->
            report_type = Map.get(args, "report_type", "sales")

            [
              %{
                role: "system",
                content: %{
                  type: "text",
                  text: "You are a report analyst. Summarize the \#{report_type} reports."
                }
              },
              %{
                role: "user",
                content: %{
                  type: "text",
                  text: "Provide a concise summary of the latest \#{report_type} reports."
                }
              }
            ]
          end
        end
      end

  ## DSL Functions

  - `description/1` — Human-readable description of the prompt
  - `argument/3` — Define an argument with name, type, and options
    - `:required` — Whether the argument is required (default: `false`)
    - `:description` — Description of the argument
    - `:default` — Default value if not provided
    - `:enum` — List of allowed values
  - `messages/1` — Callback `fn args -> [...] end` that returns a list of message maps
    Each message is `%{role: "user"|"assistant"|"system", content: %{type: "text", text: "..."}}`

  ## Arguments

  Arguments support the following types: `:string`, `:integer`, `:float`, `:boolean`,
  `:list`, `:map`, and arrays (`{:array, inner_type}`).

  Arguments with `required: true` will be validated by Anubis MCP before calling
  the `messages` callback. Missing required arguments will return a protocol error.

  ## Response Format

  The `messages` callback should return a list of message maps. Each message must have:
  - `:role` — One of `"user"`, `"assistant"`, or `"system"`
  - `:content` — A map with `:type` (`"text"`) and `:text` (the message content)

  The generated module wraps these messages in an `Anubis.Server.Response` struct
  with `type: :prompt` for proper MCP protocol encoding.
  """

  @doc """
  Defines a new prompt within an Ectomancer module.

  ## Example

      prompt :analyze_churn do
        description "Analyze user churn over a time period"
        argument :days, :integer, required: true, description: "Days to look back"

        messages fn args ->
          [
            %{
              role: "user",
              content: %{
                type: "text",
                text: "Analyze churn over the last \#{args["days"]} days"
              }
            }
          ]
        end
      end
  """
  defmacro prompt(name, do: block) do
    prompt_name_str = to_string(name)

    {description, arguments, messages_ast} = parse_prompt_block(block)

    quote do
      prompt_module_name =
        Module.concat(__MODULE__, "Prompt.#{Macro.camelize(unquote(prompt_name_str))}")

      Ectomancer.Prompt.define_prompt_module(
        prompt_module_name,
        unquote(prompt_name_str),
        unquote(Macro.escape(description)),
        unquote(Macro.escape(arguments)),
        unquote(messages_ast)
      )

      require Anubis.Server
      Anubis.Server.component(prompt_module_name, name: unquote(prompt_name_str))
    end
  end

  @doc false
  defmacro define_prompt_module(
             module_name,
             prompt_name,
             description,
             arguments,
             messages_ast
           ) do
    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(description)
        @prompt_name unquote(prompt_name)
        @arguments unquote(arguments)
        @messages_fn unquote(messages_ast)

        def name, do: @prompt_name
        def description, do: @moduledoc
        def __mcp_component_type__, do: :prompt
        def __scopes__, do: []

        def arguments do
          @arguments
        end

        def get_messages(args, frame) do
          validated_args = apply_defaults(@arguments, args || %{})

          try do
            messages = unquote(messages_ast).(validated_args)

            response =
              %Anubis.Server.Response{
                type: :prompt,
                messages: Enum.map(messages, &message_to_protocol/1)
              }

            {:reply, response, frame}
          rescue
            e ->
              error = %Anubis.MCP.Error{
                code: -32_603,
                message: "Prompt execution error: #{Exception.message(e)}",
                data: %{
                  error: inspect(e),
                  stacktrace: Exception.format_stacktrace(__STACKTRACE__)
                }
              }

              {:error, error, frame}
          end
        end

        defp message_to_protocol(%{role: role, content: %{type: type, text: text}})
             when role in ~w(user assistant system)a and type in ~w(text)a do
          %{"role" => to_string(role), "content" => %{"type" => to_string(type), "text" => text}}
        end

        defp message_to_protocol(msg) when is_map(msg) do
          msg
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> maybe_wraps_content()
        end

        defp maybe_wraps_content(%{"content" => %{"text" => _} = content} = msg) do
          msg
        end

        defp maybe_wraps_content(%{"content" => content} = msg) when is_binary(content) do
          Map.put(msg, "content", %{"type" => "text", "text" => content})
        end

        defp maybe_wraps_content(msg), do: msg

        defp apply_defaults(arguments, args) do
          Enum.reduce(arguments, args, fn arg, acc ->
            name = arg["name"]
            default = arg["default"]

            if is_nil(Map.get(acc, name)) and not is_nil(default) do
              Map.put(acc, name, default)
            else
              acc
            end
          end)
        end
      end
    end
  end

  # Parse prompt block to extract components
  defp parse_prompt_block(block) do
    items =
      case block do
        {:__block__, _, inner_items} -> flatten_block_items(inner_items)
        single -> [single]
      end

    Enum.reduce(
      items,
      {"", [], quote(do: fn _args -> [] end)},
      fn item, {desc, arguments, messages} ->
        case item do
          {:description, _, [text]} ->
            {text, arguments, messages}

          {:argument, _, [name, type | rest]} ->
            opts = extract_opts(rest)
            arg = build_argument_def(name, type, opts)
            {desc, [arg | arguments], messages}

          {:messages, _, [messages_block]} ->
            {desc, arguments, messages_block}

          _ ->
            {desc, arguments, messages}
        end
      end
    )
  end

  # Build argument definition for MCP protocol
  defp build_argument_def(name, _type, opts) do
    arg_name = to_string(name)

    arg = %{
      "name" => arg_name,
      "description" => opts[:description] || "",
      "required" => opts[:required] || false
    }

    arg =
      if opts[:default] do
        Map.put(arg, "default", opts[:default])
      else
        arg
      end

    arg =
      if opts[:enum] do
        Map.put(arg, "enum", opts[:enum])
      else
        arg
      end

    arg
  end

  @doc false
  def flatten_block_items(items) do
    Enum.flat_map(items, fn
      {:__block__, _, inner} -> flatten_block_items(inner)
      other -> [other]
    end)
  end

  defp extract_opts([]), do: []
  defp extract_opts([opts | _]), do: opts
end
