defmodule Mix.Tasks.UpdateView do
  @moduledoc """
  Required option(s): 
    --view-name <view_to_update>

  Given a configured view, makes a copy of the highest version change file. The copy file name has its 
  version bumped, a timestamp, and a user-supplied description. If the user's environment has an 
  editor which supports opening a file given a file name and line number, the copy can 
  be opened for immediate editing.

  For example, if a config file contains an entry like this:
  
  ```
  config :view_migrator,
  views: 
    %{
      my_views: [view_name: "my_view", view_directory: "assets/views/my_view/"],
    }

  ```

  and the `view_directory` contains these files: 

  ```
  1_20230928152344_initial_definition.sql
  2_20230928160432_add_a_field.sql
  ```


  then supplying the option `--view-name my_view` will prompt the user for a description of the changes to the file.
  Assuming user enters 'adds_another_field', then the contents of `2_20230928160432_add_a_field.sql` will
  be copied into a new file, `3_<yyyyMMddHHmmss>_adds_another_field.sql` in the same directory. If the user's
  environment is configured as needed, the user is  asked whether to begin editing the file immediately and opens
  the system editor if so.
  """

  use Mix.Task
  require IEx.Helpers

  @shortdoc "Copies the contents of the latest version of a view (`--view-name <view_name>`)to a new file, bumping its version and letting a user describe it"
  @impl Mix.Task
  def run(args) do
    {parsed, _, _} = OptionParser.parse(args, strict: [view_name: :string])

    view_name = parsed |> Keyword.fetch!(:view_name) |> String.to_atom() 

    current_change = 
      view_name
      |> get_view_change_dir()
      |> find_current_change_file()

    new_file =
      current_change
      |> get_version_number()
      |> solicit_user_description()
      |> make_new_file_name()
      |> copy_current_to_new(current_change) 
      |> ask_user_to_open() 

    IO.puts "Created #{new_file}"
  end

  defp get_view_change_dir(view_name) when is_atom(view_name) do
    Application.get_env(:view_migrator, :views)
    |> Map.get(view_name)
    |> Keyword.fetch!(:view_directory)
  end

  defp find_current_change_file(dir) do
    Path.join(
      dir, 
      dir |> File.ls! |> Enum.sort_by(&get_version_number/1) |> List.last()
    )
  end

  #
  defp get_version_number(file) do
    file |> Path.basename() |> String.split("_") |> hd |> String.to_integer()
  end

  defp solicit_user_description(version_number) do
    IO.puts "Versioning #{version_number} --> #{version_number+1}"
    user_input = 
      IO.gets "Enter a description of what's new in the next version e.g., 'change_abc_to_type_integer') > "
    
    {version_number+1, user_input |> String.trim()}
  end

  defp make_new_file_name({new_version_number, description}), 
  do: "#{new_version_number}_#{timestamp()}_#{description}.sql"

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  defp copy_current_to_new(new_name, current_file) do
    dir = Path.dirname current_file
    new_file = Path.join(dir, new_name)
    File.cp!(
      current_file, 
      new_file
    )

    new_file
  end

  defp ask_user_to_open(new_file) do
    editor = System.get_env("ELIXIR_EDITOR") || System.get_env("EDITOR")
    if editor && (editor =~ ~r/\+__LINE__ __FILE__/) do
      user_input = IO.gets "Do you want to edit #{new_file} now? [Yn] > "
      if user_input =~ ~r/[Yy]/ do
        IEx.Helpers.open({new_file,1})
      end
    end

    new_file
  end
end
