defmodule ViewMigrator do
  @moduledoc """
  Migration with views. 

  Exposes macros for 1) creating a view, 2) changing a view, or 3) changing a table that participates 
  in a view. This is useful in Postgres, where modifying columns which participate in a view is not supported:

  ```
  ERROR: cannot alter type of a column used by a view or rule
  ```

  The `ViewMigrator` sandwiches the usual Ecto `up` and `down` `do` blocks between view operations.

  """
   
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use Ecto.Migration
      import ViewMigrator, 
        only: [ create_view: 0, change_view: 0, change_with_view: 2 ]

      @view_directory Keyword.fetch!(opts, :view_directory)
      @view_name      Keyword.fetch!(opts, :view_name)

      @current_view_version  Keyword.fetch!(opts, :current_view_version)
      @bumping_version?      Keyword.get(opts, :bumping_version?, true)

      defp execute_view(_bumping_version?, _direction, nil, view_directory),
      do: 1 |> get_migration(view_directory) |> execute

      defp execute_view(bumping_version?, direction, current_version, view_directory) do
        bumping_version?
        |> bump_version(direction, current_version)
        |> get_migration(view_directory)
        |> execute
      end

      defp bump_version(true, :up, current_version), 
      do: current_version + 1

      defp bump_version(_bumping_version?, _direction, current_version), 
      do: current_version

      defguardp valid_version(version) 
        when is_integer(version) and version > 0

      defp get_migration(version, view_directory) when valid_version(version) do
        file = 
          view_directory
          |> fetch_and_check_view_directory_files()
          |> Enum.find(& String.starts_with?(&1, Integer.to_string(version) <> "_"))

        [view_directory, file] |> Path.join |> File.read!
      end

      defp get_sequence(files), 
      do: files |> Enum.sort() |> Enum.map(& String.to_integer(String.first(&1)))

      defp fetch_and_check_view_directory_files(view_directory) do
        files = view_directory |> File.ls!() 
        sequence = files |> get_sequence()

        unless (1..List.last(sequence)) == (List.first(sequence)..List.last(sequence)) do
          raise(
            """
              Your view directory must consist of sequentially ordered SQL files, 
              starting at 1, like '1_create_view.sql', '2_add_field.sql', etc.
            """
          )
        else 
          files
        end
      end

      defp drop_view(view_name), 
      do: "DROP VIEW IF EXISTS #{view_name}" |> execute 

    end
  end

  @doc"""
  Starts a new view. Assumes `@current_view_version` is `nil`. Simply drops the view in the `down` operation.
  """
  @spec create_view() :: Macro.t()
  defmacro create_view() do
    quote do
      def up do
        execute_view(nil,nil,nil, @view_directory) 
      end

      def down do
        drop_view(@view_name)
      end
    end
  end

  @doc """
  Change a view using a SQL file. Implicitly the version of the view is changing,
  so only the direction and not the `@bumping_version?` attribute determines which version is used
  """
  @spec change_view() :: Macro.t()
  defmacro change_view() do
    quote do
      def up do
        drop_view(@view_name)
        execute_view(true, :up, @current_view_version, @view_directory)
      end 

      def down do
        drop_view(@view_name)
        execute_view(true, :down, @current_view_version, @view_directory)
      end 
    end
  end

  @doc """
  Change an aspect of a table which participates in a view. Not all changes require a new 
  version of a view, though they always require the current version to be
  dropped and re-created. If `@bumping_version?` is explicitly set to `false`, the current 
  view is simply dropped and re-created for up and down operations.
  """
  @spec change_with_view(direction :: :up | :down, usual_ecto_expression :: Macro.t()) :: Macro.t()
  defmacro change_with_view(direction, do: expression) do
    quote do
      def unquote(direction)() do
        drop_view(@view_name)
        unquote(expression)
        execute_view(@bumping_version?, unquote(direction), @current_view_version, @view_directory)
      end 
    end
  end

end
