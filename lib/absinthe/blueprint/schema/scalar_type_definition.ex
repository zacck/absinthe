defmodule Absinthe.Blueprint.Schema.ScalarTypeDefinition do
  @moduledoc false

  alias Absinthe.Blueprint

  @enforce_keys [:name]
  defstruct [
    :name,
    :identifier,
    :module,
    description: nil,
    parse: nil,
    serialize: nil,
    directives: [],
    # Added by phases
    flags: %{},
    errors: [],
    __reference__: nil
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: nil | String.t(),
          directives: [Blueprint.Directive.t()],
          # Added by phases
          flags: Blueprint.flags_t(),
          errors: [Absinthe.Phase.Error.t()]
        }

  def build(type_def, schema) do
    %Absinthe.Type.Scalar{
      identifier: type_def.identifier,
      name: type_def.name,
      description: type_def.description
    }
  end
end
