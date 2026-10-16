# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  export: [
    locals_without_parens: [
      expose: 1,
      expose: 2,
      expose_routes: 1,
      expose_routes: 2,
      expose_oban_jobs: 0,
      expose_oban_jobs: 1,
      tool: 2,
      prompt: 2,
      resource: 2,
      description: 1,
      param: 2,
      param: 3,
      argument: 2,
      argument: 3,
      messages: 1,
      uri: 1,
      mime_type: 1,
      read: 1,
      authorize: 1,
      handle: 1
    ]
  ]
]
