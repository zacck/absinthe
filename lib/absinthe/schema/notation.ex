defmodule Absinthe.Schema.Notation do
  alias Absinthe.Blueprint
  alias Absinthe.Blueprint.Schema
  alias Absinthe.Utils

  Module.register_attribute(__MODULE__, :placement, accumulate: true)

  defmacro __using__(_opts) do
    Module.register_attribute(__CALLER__.module, :absinthe_blueprint, [])
    Module.put_attribute(__CALLER__.module, :absinthe_blueprint, [%Absinthe.Blueprint{}])
    Module.register_attribute(__CALLER__.module, :absinthe_desc, accumulate: true)

    quote do
      import Absinthe.Resolution.Helpers,
        only: [
          async: 1,
          async: 2,
          batch: 3,
          batch: 4
        ]

      Module.register_attribute(__MODULE__, :__absinthe_type_import__, accumulate: true)
      @desc nil
      import unquote(__MODULE__), only: :macros
      @before_compile unquote(__MODULE__)
    end
  end

  ### Macro API ###

  @placement {:config, [under: [:field]]}
  @doc """
  Configure a subscription field.

  ## Example

  ```elixir
  config fn args, %{context: context} ->
    if authorized?(context) do
      {:ok, topic: args.client_id}
    else
      {:error, "unauthorized"}
    end
  end
  ```

  See `Absinthe.Schema.subscription/1` for details
  """
  defmacro config(config_fun) do
    __CALLER__
    |> recordable!(:config, @placement[:config])
    |> record_config!(config_fun)
  end

  @placement {:trigger, [under: [:field]]}
  @doc """
  Set a trigger for a subscription field.

  It accepts one or more mutation field names, and can be called more than once.

  ```
  mutation do
    field :gps_event, :gps_event
    field :user_checkin, :user
  end
  subscription do
    field :location_update, :user do
      arg :user_id, non_null(:id)

      config fn args, _ ->
        {:ok, topic: args.user_id}
      end

      trigger :gps_event, topic: fn event ->
        event.user_id
      end

      trigger :user_checkin, topic: fn user ->
        [user.id, user.parent_id]
      end
    end
  end
  ```

  Trigger functions are only called once per event, so database calls within
  them do not present a significant burden.

  See the `subscription/2` macro docs for additional details
  """
  defmacro trigger(mutations, attrs) do
    __CALLER__
    |> recordable!(:trigger, @placement[:trigger])
    |> record_trigger!(List.wrap(mutations), attrs)
  end

  # OBJECT

  @placement {:object, [toplevel: true]}
  @doc """
  Define an object type.

  Adds an `Absinthe.Type.Object` to your schema.

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples

  Basic definition:

  ```
  object :car do
    # ...
  end
  ```

  Providing a custom name:

  ```
  object :car, name: "CarType" do
    # ...
  end
  ```
  """
  @reserved_identifiers ~w(query mutation subscription)a
  defmacro object(identifier, attrs \\ [], block)

  defmacro object(identifier, _attrs, _block) when identifier in @reserved_identifiers do
    raise Absinthe.Schema.Notation.Error,
          "Invalid schema notation: cannot create an `object` with reserved identifier `#{
            identifier
          }`"
  end

  defmacro object(identifier, attrs, do: block) do
    __CALLER__
    |> recordable!(:object, @placement[:object])
    |> record!(Schema.ObjectTypeDefinition, identifier, attrs, block)
  end

  @placement {:interfaces, [under: :object]}
  @doc """
  Declare implemented interfaces for an object.

  See also `interface/1`, which can be used for one interface,
  and `interface/3`, used to define interfaces themselves.

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples

  ```
  object :car do
    interfaces [:vehicle, :branded]
    # ...
  end
  ```
  """
  defmacro interfaces(ifaces) when is_list(ifaces) do
    __CALLER__
    |> recordable!(:interfaces, @placement[:interfaces])
    |> record_interfaces!(ifaces)
  end

  @placement {:resolve, [under: [:field]]}
  @doc """
  Mark a field as deprecated

  In most cases you can simply pass the deprecate: "message" attribute. However
  when using the block form of a field it can be nice to also use this macro.

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples
  ```
  field :foo, :string do
    deprecate "Foo will no longer be supported"
  end
  ```

  This is how to deprecate other things
  ```
  field :foo, :string do
    arg :bar, :integer, deprecate: "This isn't supported either"
  end

  enum :colors do
    value :red
    value :blue, deprecate: "This isn't supported"
  end
  ```
  """
  defmacro deprecate(msg) do
    __CALLER__
    |> recordable!(:deprecate, @placement[:deprecate])
    |> record_deprecate!(msg)
  end

  @doc """
  Declare an implemented interface for an object.

  Adds an `Absinthe.Type.Interface` to your schema.

  See also `interfaces/1`, which can be used for multiple interfaces,
  and `interface/3`, used to define interfaces themselves.

  ## Examples

  ```
  object :car do
    interface :vehicle
    # ...
  end
  ```
  """
  @placement {:interface_attribute, [under: :object]}
  defmacro interface(identifier) do
    __CALLER__
    |> recordable!(
      :interface_attribute,
      @placement[:interface_attribute],
      as: "`interface` (as an attribute)"
    )
    |> record_interface!(identifier)
  end

  # INTERFACES

  @placement {:interface, [toplevel: true]}
  @doc """
  Define an interface type.

  Adds an `Absinthe.Type.Interface` to your schema.

  Also see `interface/1` and `interfaces/1`, which declare
  that an object implements one or more interfaces.

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples

  ```
  interface :vehicle do
    field :wheel_count, :integer
  end

  object :rally_car do
    field :wheel_count, :integer
    interface :vehicle
  end
  ```
  """
  defmacro interface(identifier, attrs \\ [], do: block) do
    __CALLER__
    |> recordable!(:interface, @placement[:interface])
    |> record!(Schema.InterfaceTypeDefinition, identifier, attrs, block)
  end

  @placement {:resolve_type, [under: [:interface, :union]]}
  @doc """
  Define a type resolver for a union or interface.

  See also:
  * `Absinthe.Type.Interface`
  * `Absinthe.Type.Union`

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples

  ```
  interface :entity do
    # ...
    resolve_type fn
      %{employee_count: _},  _ ->
        :business
      %{age: _}, _ ->
        :person
    end
  end
  ```
  """
  defmacro resolve_type(func_ast) do
    __CALLER__
    |> recordable!(:resolve_type, @placement[:resolve_type])
    |> record_resolve_type!(func_ast)
  end

  defp replace_key(attrs, k1, k2) do
    case Keyword.fetch(attrs, k1) do
      {:ok, value} ->
        attrs
        |> Keyword.delete(k1)
        |> Keyword.put(k2, value)

      _ ->
        attrs
    end
  end

  defp handle_field_attrs(attrs, caller) do
    attrs =
      attrs
      |> expand_ast(caller)
      |> Keyword.delete(:args)
      # |> replace_key(:args, :arguments)
      |> replace_key(:deprecate, :deprecation)

    case Keyword.pop(attrs, :resolve) do
      {nil, attrs} ->
        attrs

      {ast, attrs} ->
        ast = {:{}, [], [{Absinthe.Resolution, ast}, []]}
        Keyword.update(attrs, :middleware_ast, [ast], &[ast | &1])
    end
  end

  # FIELDS
  @placement {:field, [under: [:input_object, :interface, :object]]}
  @doc """
  Defines a GraphQL field

  See `field/4`
  """
  defmacro field(identifier, do: block) do
    __CALLER__
    |> recordable!(:field, @placement[:field])
    |> record!(Schema.FieldDefinition, identifier, [], block)
  end

  defmacro field(identifier, attrs) when is_list(attrs) do
    attrs = handle_field_attrs(attrs, __CALLER__)
    __CALLER__
    |> recordable!(:field, @placement[:field])
    |> record!(Schema.FieldDefinition, identifier, attrs, [])
  end

  defmacro field(identifier, type) do
    attrs = handle_field_attrs([type: type], __CALLER__)
    __CALLER__
    |> recordable!(:field, @placement[:field])
    |> record!(Schema.FieldDefinition, identifier, attrs, [])
  end

  @doc """
  Defines a GraphQL field

  See `field/4`
  """
  defmacro field(identifier, attrs, do: block) when is_list(attrs) do
    attrs = handle_field_attrs(attrs, __CALLER__)
    __CALLER__
    |> recordable!(:field, @placement[:field])
    |> record!(Schema.FieldDefinition, identifier, attrs, block)
  end

  defmacro field(identifier, type, do: block) do
    attrs = handle_field_attrs([type: type], __CALLER__)
    __CALLER__
    |> recordable!(:field, @placement[:field])
    |> record!(Schema.FieldDefinition, identifier, attrs, block)
  end

  defmacro field(identifier, type, attrs) do
    attrs = handle_field_attrs(Keyword.put(attrs, :type, type), __CALLER__)
    __CALLER__
    |> recordable!(:field, @placement[:field])
    |> record!(Schema.FieldDefinition,identifier,attrs,[])
  end

  @doc """
  Defines a GraphQL field.

  ## Placement

  #{Utils.placement_docs(@placement)}

  `query`, `mutation`, and `subscription` are
  all objects under the covers, and thus you'll find `field` definitions under
  those as well.

  ## Examples
  ```
  field :id, :id
  field :age, :integer, description: "How old the item is"
  field :name, :string do
    description "The name of the item"
  end
  field :location, type: :location
  ```
  """
  defmacro field(identifier, type, attrs, do: block) do
    __CALLER__
    |> recordable!(:field, @placement[:field])
    |> record!(Schema.FieldDefinition, identifier, Keyword.put(attrs, :type, type), block)
  end

  @placement {:resolve, [under: [:field]]}
  @doc """
  Defines a resolve function for a field

  Specify a 2 or 3 arity function to call when resolving a field.

  You can either hard code a particular anonymous function, or have a function
  call that returns a 2 or 3 arity anonymous function. See examples for more information.

  Note that when using a hard coded anonymous function, the function will not
  capture local variables.

  ### 3 Arity Functions

  The first argument to the function is the parent entity.
  ```
  {
    user(id: 1) {
      name
    }
  }
  ```
  A resolution function on the `name` field would have the result of the `user(id: 1)` field
  as its first argument. Top level fields have the `root_value` as their first argument.
  Unless otherwise specified, this defaults to an empty map.

  The second argument to the resolution function is the field arguments. The final
  argument is an `Absinthe.Resolution` struct, which includes information like
  the `context` and other execution data.

  ### 2 Arity Function

  Exactly the same as the 3 arity version, but without the first argument (the parent entity)

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples
  ```
  query do
    field :person, :person do
      resolve &Person.resolve/2
    end
  end
  ```

  ```
  query do
    field :person, :person do
      resolve fn %{id: id}, _ ->
        {:ok, Person.find(id)}
      end
    end
  end
  ```

  ```
  query do
    field :person, :person do
      resolve lookup(:person)
    end
  end

  def lookup(:person) do
    fn %{id: id}, _ ->
      {:ok, Person.find(id)}
    end
  end
  ```
  """
  defmacro resolve(func_ast) do
    __CALLER__
    |> recordable!(:resolve, @placement[:resolve])

    quote do
      middleware Absinthe.Resolution, unquote(func_ast)
    end
  end

  @placement {:complexity, [under: [:field]]}
  defmacro complexity(func_ast) do
    __CALLER__
    |> recordable!(:complexity, @placement[:complexity])
    |> record_complexity!(func_ast)
  end

  @placement {:middleware, [under: [:field]]}
  defmacro middleware(new_middleware, opts \\ []) do
    __CALLER__
    |> recordable!(:middleware, @placement[:middleware])
    |> record_middleware!(new_middleware, opts)
  end

  @placement {:is_type_of, [under: [:object]]}
  @doc """

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro is_type_of(func_ast) do
    __CALLER__
    |> recordable!(:is_type_of, @placement[:is_type_of])
    |> record_is_type_of!(func_ast)
  end

  @placement {:arg, [under: [:directive, :field]]}
  # ARGS
  @doc """
  Add an argument.

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples

  ```
  field do
    arg :size, :integer
    arg :name, :string, description: "The desired name"
  end
  ```
  """
  defmacro arg(identifier, type, attrs) do
    __CALLER__
    |> recordable!(:arg, @placement[:arg])
    |> record_arg!(identifier, Keyword.put(attrs, :type, type))
  end

  @doc """
  Add an argument.

  See `arg/3`
  """
  defmacro arg(identifier, attrs) when is_list(attrs) do
    __CALLER__
    |> recordable!(:arg, @placement[:arg])
    |> record_arg!(identifier, attrs)
  end

  defmacro arg(identifier, type) do
    __CALLER__
    |> recordable!(:arg, @placement[:arg])
    |> record_arg!(identifier, type: type)
  end

  # SCALARS

  @placement {:scalar, [toplevel: true]}
  @doc """
  Define a scalar type

  A scalar type requires `parse/1` and `serialize/1` functions.

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples
  ```
  scalar :time, description: "ISOz time" do
    parse &Timex.parse(&1.value, "{ISOz}")
    serialize &Timex.format!(&1, "{ISOz}")
  end
  ```
  """
  defmacro scalar(identifier, attrs, do: block) do
    __CALLER__
    |> recordable!(:scalar, @placement[:scalar])
    |> record!(Schema.ScalarTypeDefinition, identifier, attrs, block)
  end

  @doc """
  Defines a scalar type

  See `scalar/3`
  """
  defmacro scalar(identifier, do: block) do
    __CALLER__
    |> recordable!(:scalar, @placement[:scalar])
    |> record!(Schema.ScalarTypeDefinition, identifier, [], block)
  end

  defmacro scalar(identifier, attrs) do
    __CALLER__
    |> recordable!(:scalar, @placement[:scalar])
    |> record!(Schema.ScalarTypeDefinition, identifier, attrs, nil)
  end

  @placement {:serialize, [under: [:scalar]]}
  @doc """
  Defines a serialization function for a `scalar` type

  The specified `serialize` function is used on outgoing data. It should simply
  return the desired external representation.

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro serialize(func_ast) do
    __CALLER__
    |> recordable!(:serialize, @placement[:serialize])
    |> record_serialize!(func_ast)
  end

  @placement {:private,
              [under: [:field, :object, :input_object, :enum, :scalar, :interface, :union]]}
  @doc false
  defmacro private(owner, key, value) do
    __CALLER__
    |> recordable!(:private, @placement[:private])
    |> record_private!(owner, [{key, value}])
  end

  @placement {:meta,
              [under: [:field, :object, :input_object, :enum, :scalar, :interface, :union]]}
  @doc """
  Defines a metadata key/value pair for a custom type.

  For more info see `meta/1`

  ### Examples

  ```
  meta :cache, false
  ```

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro meta(key, value) do
    __CALLER__
    |> recordable!(:meta, @placement[:meta])
    |> record_private!(:meta, [{key, value}])
  end

  @doc """
  Defines list of metadata's key/value pair for a custom type.

  This is generally used to facilitate libraries that want to augment Absinthe
  functionality

  ## Examples

  ```
  object :user do
    meta cache: true, ttl: 22_000
  end

  object :user, meta: [cache: true, ttl: 22_000] do
    # ...
  end
  ```

  The meta can be accessed via the `Absinthe.Type.meta/2` function.

  ```
  user_type = Absinthe.Schema.lookup_type(MyApp.Schema, :user)

  Absinthe.Type.meta(user_type, :cache)
  #=> true

  Absinthe.Type.meta(user_type)
  #=> [cache: true, ttl: 22_000]
  ```

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro meta(keyword_list) do
    __CALLER__
    |> recordable!(:meta, @placement[:meta])
    |> record_private!(:meta, keyword_list)
  end

  @placement {:parse, [under: [:scalar]]}
  @doc """
  Defines a parse function for a `scalar` type

  The specified `parse` function is used on incoming data to transform it into
  an elixir datastructure.

  It should return `{:ok, value}` or `{:error, reason}`

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro parse(func_ast) do
    __CALLER__
    |> recordable!(:parse, @placement[:parse])
    |> record_parse!(func_ast)
  end

  # DIRECTIVES

  @placement {:directive, [toplevel: true]}
  @doc """
  Defines a directive

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples

  ```
  directive :mydirective do

    arg :if, non_null(:boolean), description: "Skipped when true."

    on Language.FragmentSpread
    on Language.Field
    on Language.InlineFragment

    instruction fn
      %{if: true} ->
        :skip
      _ ->
        :include
    end

  end
  ```
  """
  defmacro directive(identifier, attrs \\ [], do: block) do
    __CALLER__
    |> recordable!(:directive, @placement[:directive])
    |> record_directive!(identifier, attrs, block)
  end

  @placement {:on, [under: :directive]}
  @doc """
  Declare a directive as operating an a AST node type

  See `directive/2`

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro on(ast_node) do
    __CALLER__
    |> recordable!(:on, @placement[:on])
    |> record_locations!(ast_node)
  end

  @placement {:instruction, [under: :directive]}
  @doc """
  Calculate the instruction for a directive

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro instruction(func_ast) do
    __CALLER__
    |> recordable!(:instruction, @placement[:instruction])
    |> record_instruction!(func_ast)
  end

  @placement {:expand, [under: :directive]}
  @doc """
  Define the expansion for a directive

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro expand(func_ast) do
    __CALLER__
    |> recordable!(:expand, @placement[:expand])
    |> record_expand!(func_ast)
  end

  # INPUT OBJECTS

  @placement {:input_object, [toplevel: true]}
  @doc """
  Defines an input object

  See `Absinthe.Type.InputObject`

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples
  ```
  input_object :contact_input do
    field :email, non_null(:string)
  end
  ```
  """
  defmacro input_object(identifier, attrs \\ [], do: block) do
    __CALLER__
    |> recordable!(:input_object, @placement[:input_object])
    |> record!(Schema.InputObjectTypeDefinition, identifier, attrs, block)
  end

  # UNIONS

  @placement {:union, [toplevel: true]}
  @doc """
  Defines a union type

  See `Absinthe.Type.Union`

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples
  ```
  union :search_result do
    description "A search result"

    types [:person, :business]
    resolve_type fn
      %Person{}, _ -> :person
      %Business{}, _ -> :business
    end
  end
  ```
  """
  defmacro union(identifier, attrs \\ [], do: block) do
    __CALLER__
    |> recordable!(:union, @placement[:union])
    |> record!(Schema.UnionTypeDefinition, identifier, attrs, block)
  end

  @placement {:types, [under: [:union]]}
  @doc """
  Defines the types possible under a union type

  See `union/3`

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro types(types) do
    __CALLER__
    |> recordable!(:types, @placement[:types])
    |> record_types!(types)
  end

  # ENUMS

  @placement {:enum, [toplevel: true]}
  @doc """
  Defines an enum type

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples

  Handling `RED`, `GREEN`, `BLUE` values from the query document:

  ```
  enum :color do
    value :red
    value :green
    value :blue
  end
  ```

  A given query document might look like:

  ```graphql
  {
    foo(color: RED)
  }
  ```

  Internally you would get an argument in elixir that looks like:

  ```elixir
  %{color: :red}
  ```

  If your return value is an enum, it will get serialized out as:

  ```json
  {"color": "RED"}
  ```

  You can provide custom value mappings. Here we use `r`, `g`, `b` values:

  ```
  enum :color do
    value :red, as: "r"
    value :green, as: "g"
    value :blue, as: "b"
  end
  ```

  """
  defmacro enum(identifier, attrs, do: block) do
    __CALLER__
    |> recordable!(:enum, @placement[:enum])
    |> record!(Schema.EnumTypeDefinition, identifier, attrs, block)
  end

  @doc """
  Defines an enum type

  See `enum/3`
  """
  defmacro enum(identifier, do: block) do
    __CALLER__
    |> recordable!(:enum, @placement[:enum])
    |> record!(Schema.EnumTypeDefinition, identifier, [], block)
  end

  defmacro enum(identifier, attrs) do
    __CALLER__
    |> recordable!(:enum, @placement[:enum])
    |> record!(Schema.EnumTypeDefinition, identifier, attrs, nil)
  end

  @placement {:value, [under: [:enum]]}
  @doc """
  Defines a value possible under an enum type

  See `enum/3`

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro value(identifier, raw_attrs \\ []) do
    __CALLER__
    |> recordable!(:value, @placement[:value])
    |> record_value!(identifier, raw_attrs)
  end

  # GENERAL ATTRIBUTES

  @placement {:description, [toplevel: false]}
  @doc """
  Defines a description

  This macro adds a description to any other macro which takes a block.

  Note that you can also specify a description by using `@desc` above any item
  that can take a description attribute.

  ## Placement

  #{Utils.placement_docs(@placement)}
  """
  defmacro description(text) do
    __CALLER__
    |> recordable!(:description, @placement[:description])
    |> record_description!(text)
  end

  # TYPE UTILITIES
  @doc """
  Marks a type reference as non null

  See `field/3` for examples
  """
  defmacro non_null(type) do
    %Absinthe.Type.NonNull{of_type: type}
  end

  @doc """
  Marks a type reference as a list of the given type

  See `field/3` for examples
  """
  defmacro list_of(type) do
    %Absinthe.Type.List{of_type: type}
  end

  @placement {:import_fields, [under: [:input_object, :interface, :object]]}
  @doc """
  Import fields from another object

  ## Example
  ```
  object :news_queries do
    field :all_links, list_of(:link)
    field :main_story, :link
  end

  object :admin_queries do
    field :users, list_of(:user)
    field :pending_posts, list_of(:post)
  end

  query do
    import_fields :news_queries
    import_fields :admin_queries
  end
  ```

  Import fields can also be used on objects created inside other modules that you
  have used import_types on.

  ```
  defmodule MyApp.Schema.NewsTypes do
    use Absinthe.Schema.Notation

    object :news_queries do
      field :all_links, list_of(:link)
      field :main_story, :link
    end
  end
  defmodule MyApp.Schema.Schema do
    use Absinthe.Schema

    import_types MyApp.Schema.NewsTypes

    query do
      import_fields :news_queries
      # ...
    end
  end
  ```
  """
  defmacro import_fields(source_criteria, opts \\ []) do
    source_criteria =
      source_criteria
      |> Macro.prewalk(&Macro.expand(&1, __CALLER__))

    put_attr(__CALLER__.module, {:import_fields, {source_criteria, opts}})
  end

  @placement {:import_types, [toplevel: true]}
  @doc """
  Import types from another module

  Very frequently your schema module will simply have the `query` and `mutation`
  blocks, and you'll want to break out your other types into other modules. This
  macro imports those types for use the current module

  ## Placement

  #{Utils.placement_docs(@placement)}

  ## Examples
  ```
  import_types MyApp.Schema.Types

  import_types MyApp.Schema.Types.{TypesA, TypesB}
  ```
  """
  defmacro import_types(type_module_ast, opts \\ []) do
    env = __CALLER__

    type_module_ast
    |> Macro.expand(env)
    |> do_import_types(env, opts)
  end

  defmacro values(values) do
    __CALLER__
    |> record_values!(values)
  end

  ### Recorders ###
  #################

  @scoped_types [
    Schema.ObjectTypeDefinition,
    Schema.FieldDefinition,
    Schema.ScalarTypeDefinition,
    Schema.EnumTypeDefinition,
    Schema.InputObjectTypeDefinition,
    Schema.UnionTypeDefinition,
    Schema.InterfaceTypeDefinition,
    Schema.DirectiveDefinition
  ]

  def record!(env, type, identifier, attrs, block) when type in @scoped_types do
    attrs = expand_ast(attrs, env)
    scoped_def(env, type, identifier, attrs, block)
  end

  def record_arg!(env, identifier, attrs) do
    attrs = Keyword.put(attrs, :identifier, identifier)
    attrs = Keyword.put(attrs, :name, to_string(identifier))
    arg = struct!(Schema.InputValueDefinition, attrs)
    put_attr(env.module, arg)
  end

  @doc false
  # Record a union type
  # def record_union!(env, identifier, attrs, block) do
  #   attrs = Keyword.put(attrs, :identifier, identifier)
  #   scoped_def(env, Schema., identifier, attrs, block)
  # end
  #
  # @doc false
  # # Record an input object type
  # def record_input_object!(env, identifier, attrs, block) do
  #   attrs = Keyword.put(attrs, :identifier, identifier)
  #   scoped_def(env, :input_object, identifier, attrs, block)
  # end

  @doc false
  # Record a directive expand function in the current scope
  def record_expand!(env, func_ast) do
    # Scope.put_attribute(env.module, :expand, func_ast)
    # Scope.recorded!(env.module, :attr, :expand)
    # :ok
  end

  @doc false
  # Record a directive instruction function in the current scope
  def record_instruction!(env, func_ast) do
    # Scope.put_attribute(env.module, :instruction, func_ast)
    # Scope.recorded!(env.module, :attr, :instruction)
    # :ok
  end

  @doc false
  # Record directive AST nodes in the current scope
  def record_locations!(env, ast_node) do
    # ast_node
    # |> List.wrap()
    # |> Enum.each(fn value ->
    #   Scope.put_attribute(
    #     env.module,
    #     :locations,
    #     value,
    #     accumulate: true
    #   )
    #
    #   Scope.recorded!(env.module, :attr, :locations)
    # end)
    #
    # :ok
  end

  @doc false
  # Record a directive
  def record_directive!(env, identifier, attrs, block) do
    attrs = Keyword.put(attrs, :identifier, identifier)
    scoped_def(env, Schema.DirectiveDefinition, identifier, attrs, block)
  end

  @doc false
  # Record a parse function in the current scope
  def record_parse!(env, fun_ast) do
    put_attr(env.module, {:parse, fun_ast})
  end

  @doc false
  # Record private values
  def record_private!(env, owner, keyword_list) when is_list(keyword_list) do
    # owner = expand(owner, env)
    # keyword_list = expand(keyword_list, env)
    #
    # keyword_list
    # |> Enum.each(fn {k, v} -> do_record_private!(env, owner, k, v) end)
  end

  defp do_record_private!(env, owner, key, value) do
    # new_attrs =
    #   Scope.current(env.module).attrs
    #   |> Keyword.put_new(:__private__, [])
    #   |> update_in([:__private__, owner], &List.wrap(&1))
    #   |> put_in([:__private__, owner, key], value)
    #
    # Scope.put_attribute(env.module, :__private__, new_attrs[:__private__])
    # :ok
  end

  @doc false
  # Record a serialize function in the current scope
  def record_serialize!(env, fun_ast) do
    put_attr(env.module, {:serialize, fun_ast})
  end

  @doc false
  # Record a type checker in the current scope
  def record_is_type_of!(env, func_ast) do
    # Scope.put_attribute(env.module, :is_type_of, func_ast)
    # Scope.recorded!(env.module, :attr, :is_type_of)
    # :ok
  end

  @doc false
  # Record a complexity analyzer in the current scope
  def record_complexity!(env, func_ast) do
    # Scope.put_attribute(env.module, :complexity, func_ast)
    # Scope.recorded!(env.module, :attr, :complexity)
    # :ok
  end

  @doc false
  # Record a type resolver in the current scope
  def record_resolve_type!(env, func_ast) do
    # Scope.put_attribute(env.module, :resolve_type, func_ast)
    # Scope.recorded!(env.module, :attr, :resolve_type)
    # :ok
  end

  @doc false
  # Record an implemented interface in the current scope
  def record_interface!(env, identifier) do
    # Scope.put_attribute(env.module, :interfaces, identifier, accumulate: true)
    # Scope.recorded!(env.module, :attr, :interface)
    # :ok
  end

  @doc false
  # Record a deprecation in the current scope
  def record_deprecate!(env, msg) do
    # Scope.put_attribute(env.module, :deprecate, msg)
    # :ok
  end

  @doc false
  # Record a list of implemented interfaces in the current scope
  def record_interfaces!(env, ifaces) do
    # Enum.each(ifaces, &record_interface!(env, &1))
    # :ok
  end

  @doc false
  # Record a list of member types for a union in the current scope
  def record_types!(env, types) do
    # Scope.put_attribute(env.module, :types, List.wrap(types))
    # Scope.recorded!(env.module, :attr, :types)
    # :ok
  end

  @doc false
  # Record an enum type
  def record_enum!(env, identifier, attrs, block) do
    attrs = expand_ast(attrs, env)
    attrs = Keyword.put(attrs, :identifier, identifier)
    scoped_def(env, :enum, identifier, attrs, block)
  end

  defp reformat_description(text), do: String.trim(text)

  @doc false
  # Record a description in the current scope
  def record_description!(env, text_block) do
    text = reformat_description(text_block)
    put_attr(env.module, {:desc, text})
  end

  @doc false
  # Record an enum value in the current scope
  def record_value!(env, identifier, raw_attrs) do
    # attrs =
    #   raw_attrs
    #   |> Keyword.put(:value, Keyword.get(raw_attrs, :as, identifier))
    #   |> Keyword.delete(:as)
    #   |> add_description(env)
    #
    # Scope.put_attribute(env.module, :values, {identifier, attrs}, accumulate: true)
    # Scope.recorded!(env.module, :attr, :value)
    # :ok
  end

  @doc false
  # Record an enum value in the current scope
  def record_values!(env, values) do
    put_attr(env.module, {:values, values})
  end

  def record_config!(env, fun_ast) do
    []
  end

  def record_trigger!(env, mutations, attrs) do
    []
  end

  def record_middleware!(env, new_middleware, opts) do
    new_middleware =
      case expand_ast(new_middleware, env) do
        {module, fun} ->
          {:{}, [], [{module, fun}, opts]}

        atom when is_atom(atom) ->
          case Atom.to_string(atom) do
            "Elixir." <> _ ->
              {:{}, [], [{atom, :call}, opts]}

            _ ->
              {:{}, [], [{env.module, atom}, opts]}
          end

        val ->
          val
      end

    put_attr(env.module, {:middleware, new_middleware})
  end

  # ------------------------------

  defmacro close_scope() do
    put_attr(__CALLER__.module, :close)
  end

  def put_reference(attrs, env, identifier) do
    Keyword.put(attrs, :__reference__, %{
      module: env.module,
      identifier: identifier,
      location: %{
        file: env.file,
        line: env.line
      }
    })
  end

  defp scoped_def(caller, type, identifier, attrs, body) do
    attrs =
      attrs
      |> Keyword.put(:identifier, identifier)
      |> Keyword.put_new(:name, default_name(type, identifier))
      |> Keyword.put(:module, caller.module)
      |> put_reference(caller, identifier)

    scalar = struct!(type, attrs)

    put_attr(caller.module, scalar)

    [
      quote do
        unquote(__MODULE__).put_desc(__MODULE__, unquote(type), unquote(identifier))
      end,
      body,
      quote(do: unquote(__MODULE__).close_scope())
    ]
  end

  defp put_attr(module, thing) do
    existing = Module.get_attribute(module, :absinthe_blueprint)
    Module.put_attribute(module, :absinthe_blueprint, [thing | existing])
    []
  end

  defp default_name(Schema.FieldDefinition, identifier) do
    identifier
    |> Atom.to_string()
  end

  defp default_name(_, identifier) do
    identifier
    |> Atom.to_string()
    |> Absinthe.Utils.camelize()
  end

  defp do_import_types({{:., _, [root_ast, :{}]}, _, modules_ast_list}, env, opts) do
    {:__aliases__, _, root} = root_ast

    root_module = Module.concat(root)
    root_module_with_alias = Keyword.get(env.aliases, root_module, root_module)

    for {_, _, leaf} <- modules_ast_list do
      type_module = Module.concat([root_module_with_alias | leaf])

      if Code.ensure_loaded?(type_module) do
        do_import_types(type_module, env, opts)
      else
        raise ArgumentError, "module #{type_module} is not available"
      end
    end
  end

  defp do_import_types(module, env, opts) do
    Module.put_attribute(env.module, :__absinthe_type_imports__, [
      {module, opts} | Module.get_attribute(env.module, :__absinthe_type_imports__) || []
    ])

    []
  end

  def put_desc(module, type, identifier) do
    Module.put_attribute(
      module,
      :absinthe_desc,
      {{type, identifier}, Module.get_attribute(module, :desc)}
    )

    Module.put_attribute(module, :desc, nil)
  end

  def noop(_desc) do
    :ok
  end

  defmacro __before_compile__(env) do
    module_attribute_descs =
      env.module
      |> Module.get_attribute(:absinthe_desc)
      |> Map.new()

    attrs =
      env.module
      |> Module.get_attribute(:absinthe_blueprint)
      |> List.insert_at(0, :close)
      |> Enum.reverse()
      |> intersperse_descriptions(module_attribute_descs)

    imports =
      (Module.get_attribute(env.module, :__absinthe_type_imports__) || [])
      |> Enum.uniq()
      |> Enum.map(fn
        module when is_atom(module) -> {module, []}
        other -> other
      end)

    schema_def = %Schema.SchemaDefinition{
      imports: imports,
      module: env.module
    }

    blueprint =
      attrs
      |> List.insert_at(1, schema_def)
      |> Absinthe.Blueprint.Schema.build()

    # TODO: handle multiple schemas
    [schema] = blueprint.schema_definitions

    functions = build_functions(schema)

    quote do
      unquote(__MODULE__).noop(@desc)

      def __absinthe_blueprint__ do
        unquote(Macro.escape(blueprint))
      end

      unquote_splicing(functions)
    end
  end

  def build_functions(schema) do
    Enum.flat_map(schema.types, &functions_for_type/1)
  end

  def grab_functions(type, module, identifier, attrs) do
    for attr <- attrs do
      value = Map.fetch!(type, attr)

      quote do
        def __absinthe_function__(unquote(module), unquote(identifier), unquote(attr)) do
          unquote(value)
>>>>>>> help-zacck
        end
      end
    end
  end

  defp functions_for_type(%Schema.ScalarTypeDefinition{} = type) do
    grab_functions(type, Absinthe.Type.Scalar, type.identifier, [:serialize, :parse])
  end

  defp functions_for_type(%Schema.ObjectTypeDefinition{} = type) do
    functions = grab_functions(type, Absinthe.Type.Object, type.identifier, [:is_type_of])

    field_functions =
      for field <- type.fields do
        identifier = {type.identifier, field.identifier}
        middleware = __ensure_middleware__(field.middleware_ast, field.identifier, type.identifier)

<<<<<<< HEAD
    funcs = [scalar_parsers | funcs]


    middleware =
      for %Schema.ObjectTypeDefinition{} = type <- schema.types,
          field <- type.fields do
        quote do
          def __absinthe_function__(Absinthe.Type.Object, unquote(type.identifier), {unquote(field.identifier), :middleware}) do
            unquote(field.middleware_ast)
=======
        quote do
          def __absinthe_function__(
                unquote(Absinthe.Type.Field),
                unquote(identifier),
                :middleware
              ) do
            unquote(middleware)
>>>>>>> help-zacck
          end
        end
      end

<<<<<<< HEAD
    funcs = [middleware | funcs]
=======
    functions ++ field_functions
  end

  defp functions_for_type(%Schema.InputObjectTypeDefinition{}) do
    []
  end

  defp functions_for_type(%Schema.EnumTypeDefinition{}) do
    []
  end

  defp functions_for_type(%Schema.UnionTypeDefinition{} = type) do
    grab_functions(type, Absinthe.Type.Union, type.identifier, [:resolve_type])
  end

  defp functions_for_type(%Schema.InterfaceTypeDefinition{} = type) do
    grab_functions(type, Absinthe.Type.Interface, type.identifier, [:resolve_type])
  end

  @doc false
  def __ensure_middleware__([], _field, :subscription) do
    [Absinthe.Middleware.PassParent]
  end

  def __ensure_middleware__([], identifier, _) do
    [{Absinthe.Middleware.MapGet, identifier}]
  end

  def __ensure_middleware__(middleware, _field, _object) do
    middleware
>>>>>>> help-zacck
  end

  defp intersperse_descriptions(attrs, descs) do
    Enum.flat_map(attrs, fn
      %struct{identifier: identifier} = val ->
        case Map.get(descs, {struct, identifier}) do
          nil -> [val]
          desc -> [val, {:desc, desc}]
        end

      val ->
        [val]
    end)
  end

  defp expand_ast(ast, env) do
    Macro.prewalk(ast, fn
      {_, _, _} = node ->
        Macro.expand(node, env)

      node ->
        node
    end)
  end

  @doc false
  # Ensure the provided operation can be recorded in the current environment,
  # in the current scope context
  def recordable!(env, _usage) do
    env
  end

  def recordable!(env, _usage, _kw_rules, _opts \\ []) do
    env
  end
end
