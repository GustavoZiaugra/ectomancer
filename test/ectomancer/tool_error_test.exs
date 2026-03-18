defmodule Ectomancer.Tool.ErrorTest do
  use ExUnit.Case

  describe "format_error with database constraint errors" do
    test "handles duplicate key error from PostgreSQL" do
      error_msg =
        "Database error: ** (Postgrex.Error) ERROR 23505 (unique_violation): duplicate key value violates unique constraint \"users_email_index\""

      {code, message, data} = Ectomancer.Tool.format_error(error_msg)

      assert code == -32_602
      assert message == "Duplicate value: Record with this value already exists"
      assert data[:details] == error_msg
    end

    test "handles foreign key violation from PostgreSQL" do
      error_msg =
        "Database error: ** (Postgrex.Error) ERROR 23503 (foreign_key_violation): violates foreign key constraint \"hooks_company_id_fkey\""

      {code, message, data} = Ectomancer.Tool.format_error(error_msg)

      assert code == -32_602
      assert message == "Invalid reference: Related record does not exist"
      assert data[:details] == error_msg
    end

    test "handles not null constraint from PostgreSQL" do
      error_msg =
        "Database error: ** (Postgrex.Error) ERROR 23502 (not_null_violation): null value in column \"email\" violates not-null constraint"

      {code, message, data} = Ectomancer.Tool.format_error(error_msg)

      assert code == -32_602
      assert message == "Missing required parameter: Email"
      assert data[:field] == "email"
    end
  end
end
