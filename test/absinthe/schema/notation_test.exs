defmodule Absinthe.Schema.NotationTest do
  use Absinthe.Case, async: true

  @moduletag :pending

  describe "import fields" do
    test "fields can be imported" do
      defmodule Foo do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :foo do
          field :name, :string
        end

        object :bar do
          import_fields :foo
          field :email, :string
        end
      end

      assert [:email, :name] = Foo.__absinthe_type__(:bar).fields |> Map.keys() |> Enum.sort()
    end

    test "works for input objects" do
      defmodule InputFoo do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        input_object :foo do
          field :name, :string
        end

        input_object :bar do
          import_fields :foo
          field :email, :string
        end
      end

      fields = InputFoo.__absinthe_type__(:bar).fields

      assert [:email, :name] = fields |> Map.keys() |> Enum.sort()
    end

    test "can work transitively" do
      defmodule Bar do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :foo do
          field :name, :string
        end

        object :bar do
          import_fields :foo
          field :email, :string
        end

        object :baz do
          import_fields :bar
          field :age, :integer
        end
      end

      assert [:age, :email, :name] ==
               Bar.__absinthe_type__(:baz).fields |> Map.keys() |> Enum.sort()
    end

    test "raises errors nicely" do
      defmodule ErrorSchema do
        use Absinthe.Schema.Notation

        object :bar do
          import_fields :asdf
          field :email, :string
        end
      end

      assert [error] = ErrorSchema.__absinthe_errors__()

      assert %{
               data: %{
                 artifact:
                   "Field Import Error\n\nObject :bar imports fields from :asdf but\n:asdf does not exist in the schema!",
                 value: :asdf
               },
               location: %{file: _, line: _},
               rule: Absinthe.Schema.Rule.FieldImportsExist
             } = error
    end

    test "handles circular errors" do
      defmodule Circles do
        use Absinthe.Schema.Notation

        object :foo do
          import_fields :bar
          field :name, :string
        end

        object :bar do
          import_fields :foo
          field :email, :string
        end
      end

      assert [error] = Circles.__absinthe_errors__()

      assert %{
               data: %{
                 artifact:
                   "Field Import Cycle Error\n\nField Import in object `foo' `import_fields(:bar) forms a cycle via: (`foo' => `bar' => `foo')",
                 value: :bar
               },
               location: %{file: _, line: _},
               rule: Absinthe.Schema.Rule.NoCircularFieldImports
             } = error
    end

    test "can import types from more than one thing" do
      defmodule Multiples do
        use Absinthe.Schema

        object :foo do
          field :name, :string
        end

        object :bar do
          field :email, :string
        end

        query do
          import_fields :foo
          import_fields :bar
          field :age, :integer
        end
      end

      assert [:age, :email, :name] ==
               Multiples.__absinthe_type__(:query).fields |> Map.keys() |> Enum.sort()
    end

    test "can import fields from imported types" do
      defmodule Source1 do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :foo do
          field :name, :string
        end
      end

      defmodule Source2 do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :bar do
          field :email, :string
        end
      end

      defmodule Dest do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        import_types Source1
        import_types Source2

        object :baz do
          import_fields :foo
          import_fields :bar
        end
      end

      assert [:email, :name] = Dest.__absinthe_type__(:baz).fields |> Map.keys() |> Enum.sort()
    end
  end

  describe "arg" do
    test "can be under field as an attribute" do
      assert_no_notation_error("ArgFieldValid", """
      object :foo do
        field :picture, :string do
          arg :size, :integer
        end
      end
      """)
    end

    test "can be under directive as an attribute" do
      assert_no_notation_error("ArgDirectiveValid", """
      directive :test do
        arg :if, :boolean
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "ArgToplevelInvalid",
        """
        arg :name, :string
        """,
        "Invalid schema notation: `arg` must only be used within `directive`, `field`"
      )
    end
  end

  describe "directive" do
    test "can be toplevel" do
      assert_no_notation_error("DirectiveValid", """
      directive :foo do
      end
      """)
    end

    test "cannot be non-toplevel" do
      assert_notation_error(
        "DirectiveInvalid",
        """
        directive :foo do
          directive :bar do
          end
        end
        """,
        "Invalid schema notation: `directive` must only be used toplevel"
      )
    end
  end

  describe "enum" do
    test "can be toplevel" do
      assert_no_notation_error("EnumValid", """
      enum :foo do
      end
      """)
    end

    test "cannot be non-toplevel" do
      assert_notation_error(
        "EnumInvalid",
        """
        enum :foo do
          enum :bar do
          end
        end
        """,
        "Invalid schema notation: `enum` must only be used toplevel"
      )
    end
  end

  describe "field" do
    test "can be under object as an attribute" do
      assert_no_notation_error("FieldObjectValid", """
      object :bar do
        field :name, :string
      end
      """)
    end

    test "can be under input_object as an attribute" do
      assert_no_notation_error("FieldInputObjectValid", """
      input_object :bar do
        field :name, :string
      end
      """)
    end

    test "can be under interface as an attribute" do
      assert_no_notation_error("FieldInterfaceValid", """
      interface :bar do
        field :name, :string
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "FieldToplevelInvalid",
        """
        field :foo, :string
        """,
        "Invalid schema notation: `field` must only be used within `input_object`, `interface`, `object`"
      )
    end
  end

  describe "input_object" do
    test "can be toplevel" do
      assert_no_notation_error("InputObjectValid", """
      input_object :foo do
      end
      """)
    end

    test "cannot be non-toplevel" do
      assert_notation_error(
        "InputObjectInvalid",
        """
        input_object :foo do
          input_object :bar do
          end
        end
        """,
        "Invalid schema notation: `input_object` must only be used toplevel"
      )
    end
  end

  describe "instruction" do
    test "can be under directive as an attribute" do
      assert_no_notation_error("InstructionValid", """
      directive :bar do
        instruction fn -> :ok end
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "InstructionToplevelInvalid",
        """
        instruction fn -> :ok end
        """,
        "Invalid schema notation: `instruction` must only be used within `directive`"
      )
    end

    test "cannot be within object" do
      assert_notation_error(
        "InstructionObjectInvalid",
        """
        object :foo do
          instruction fn -> :ok end
        end
        """,
        "Invalid schema notation: `instruction` must only be used within `directive`"
      )
    end
  end

  describe "interface" do
    test "can be toplevel" do
      assert_no_notation_error("InterfaceToplevelValid", """
      interface :foo do
        field :name, :string
        resolve_type fn _, _ -> :bar end
      end
      """)
    end

    test "can be under object as an attribute" do
      assert_no_notation_error("InterfaceObjectValid", """
      interface :foo do
        field :name, :string
        resolve_type fn _, _ -> :bar end
      end
      object :bar do
        interface :foo
        field :name, :string
      end
      """)
    end

    test "cannot be under input_object as an attribute" do
      assert_notation_error(
        "InterfaceInputObjectInvalid",
        """
        interface :foo do
          field :name, :string
          resolve_type fn _, _ -> :bar end
        end
        input_object :bar do
          interface :foo
        end
        """,
        "Invalid schema notation: `interface` (as an attribute) must only be used within `object`"
      )
    end
  end

  describe "interfaces" do
    test "can be under object as an attribute" do
      assert_no_notation_error("InterfacesValid", """
      interface :bar do
        field :name, :string
        resolve_type fn _, _ -> :foo end
      end
      object :foo do
        field :name, :string
        interfaces [:bar]
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "InterfacesInvalid",
        """
        interface :bar do
          field :name, :string
        end
        interfaces [:bar]
        """,
        "Invalid schema notation: `interfaces` must only be used within `object`"
      )
    end
  end

  describe "is_type_of" do
    test "can be under object as an attribute" do
      assert_no_notation_error("IsTypeOfValid", """
      object :bar do
        is_type_of fn _, _ -> true end
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "IsTypeOfToplevelInvalid",
        """
        is_type_of fn _, _ -> true end
        """,
        "Invalid schema notation: `is_type_of` must only be used within `object`"
      )
    end

    test "cannot be within interface" do
      assert_notation_error(
        "IsTypeOfInterfaceInvalid",
        """
        interface :foo do
          is_type_of fn _, _ -> :bar end
        end
        """,
        "Invalid schema notation: `is_type_of` must only be used within `object`"
      )
    end
  end

  describe "object" do
    test "can be toplevel" do
      assert_no_notation_error("ObjectValid", """
      object :foo do
      end
      """)
    end

    test "cannot be non-toplevel" do
      assert_notation_error(
        "ObjectInvalid",
        """
        object :foo do
          object :bar do
          end
        end
        """,
        "Invalid schema notation: `object` must only be used toplevel"
      )
    end

    test "cannot use reserved identifiers" do
      assert_notation_error(
        "ReservedIdentifierSubscription",
        """
        object :subscription do
        end
        """,
        "Invalid schema notation: cannot create an `object` with reserved identifier `subscription`"
      )

      assert_notation_error(
        "ReservedIdentifierQuery",
        """
        object :query do
        end
        """,
        "Invalid schema notation: cannot create an `object` with reserved identifier `query`"
      )

      assert_notation_error(
        "ReservedIdentifierMutation",
        """
        object :mutation do
        end
        """,
        "Invalid schema notation: cannot create an `object` with reserved identifier `mutation`"
      )
    end
  end

  describe "on" do
    test "can be under directive as an attribute" do
      assert_no_notation_error("OnValid", """
      directive :foo do
        on [Foo, Bar]
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "OnInvalid",
        """
        on [Foo, Bar]
        """,
        "Invalid schema notation: `on` must only be used within `directive`"
      )
    end
  end

  describe "parse" do
    test "can be under scalar as an attribute" do
      assert_no_notation_error("ParseValid", """
      scalar :foo do
        parse &(&1)
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "ParseInvalid",
        """
        parse &(&1)
        """,
        "Invalid schema notation: `parse` must only be used within `scalar`"
      )
    end
  end

  describe "resolve" do
    test "can be under field as an attribute" do
      assert_no_notation_error("ResolveValid", """
      object :bar do
        field :foo, :integer do
          resolve fn _, _, _ -> {:ok, 1} end
        end
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "ResolveInvalid",
        """
        resolve fn _, _ -> {:ok, 1} end
        """,
        "Invalid schema notation: `resolve` must only be used within `field`"
      )
    end

    test "cannot be within object" do
      assert_notation_error(
        "ResolveInvalid2",
        """
        object :foo do
          resolve fn _, _ -> {:ok, 1} end
        end
        """,
        "Invalid schema notation: `resolve` must only be used within `field`"
      )
    end
  end

  describe "resolve_type" do
    test "can be under interface as an attribute" do
      assert_no_notation_error("ResolveTypeValidInterface", """
      interface :bar do
        resolve_type fn _, _ -> :baz end
      end
      """)
    end

    test "can be under union as an attribute" do
      assert_no_notation_error("ResolveTypeValidUnion", """
        union :bar do
          resolve_type fn _, _ -> :baz end
        end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "ResolveTypeInvalidToplevel",
        """
        resolve_type fn _, _ -> :bar end
        """,
        "Invalid schema notation: `resolve_type` must only be used within `interface`, `union`"
      )
    end

    test "cannot be within object" do
      assert_notation_error(
        "ResolveTypeInvalidObject",
        """
        object :foo do
          resolve_type fn _, _ -> :bar end
        end
        """,
        "Invalid schema notation: `resolve_type` must only be used within `interface`, `union`"
      )
    end
  end

  describe "scalar" do
    test "can be toplevel" do
      assert_no_notation_error("ScalarValid", """
      scalar :foo do
      end
      """)
    end

    test "cannot be non-toplevel" do
      assert_notation_error(
        "ScalarInvalid",
        """
        scalar :foo do
          scalar :bar do
          end
        end
        """,
        "Invalid schema notation: `scalar` must only be used toplevel"
      )
    end
  end

  describe "serialize" do
    test "can be under scalar as an attribute" do
      assert_no_notation_error("SerializeValid", """
      scalar :foo do
        serialize &(&1)
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "SerializeInvalid",
        """
        serialize &(&1)
        """,
        "Invalid schema notation: `serialize` must only be used within `scalar`"
      )
    end
  end

  describe "types" do
    test "can be under union as an attribute" do
      assert_no_notation_error("TypesValid", """
      object :audi do
      end
      object :volvo do
      end
      union :brand do
        types [:audi, :volvo]
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "TypesInvalid",
        "types [:foo]",
        "Invalid schema notation: `types` must only be used within `union`"
      )
    end
  end

  describe "value" do
    test "can be under enum as an attribute" do
      assert_no_notation_error("ValueValid", """
      enum :color do
        value :red
        value :green
        value :blue
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "ValueInvalid",
        "value :b",
        "Invalid schema notation: `value` must only be used within `enum`"
      )
    end
  end

  describe "description" do
    test "can be under object as an attribute" do
      assert_no_notation_error("DescriptionValid", """
      object :item do
        description \"""
        Here's a description
        \"""
      end
      """)
    end

    test "cannot be toplevel" do
      assert_notation_error(
        "DescriptionInvalid",
        ~s(description "test"),
        "Invalid schema notation: `description` must not be used toplevel"
      )
    end
  end

  @doc """
  Assert a notation error occurs.

  ## Examples

  ```
  iex> assert_notation_error(\"""
  object :bar do
    field :name, :string
  end
  \""")
  ```
  """
  def assert_notation_error(name, text, message) do
    assert_raise(Absinthe.Schema.Notation.Error, message, fn ->
      """
      defmodule MyTestSchema.#{name} do
        use Absinthe.Schema

        query do
          #Query type must exist
        end

        #{text}
      end
      """
      |> Code.eval_string()
    end)
  end

  def assert_no_notation_error(name, text) do
    assert """
           defmodule MyTestSchema.#{name} do
             use Absinthe.Schema

             query do
               #Query type must exist
             end

             #{text}
           end
           """
           |> Code.eval_string()
  end
end
