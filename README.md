# ViewMigrator

This library provides macros and mix tasks that facilitate the use of database views with Ecto.

### Project Examples

1) Configuration

Assume a Postgres database view named "summaries" 

```elixir
# config/config.exs

config :view_migrator,
  views: 
    %{
      summaries: [view_name: "summaries", view_directory: "assets/views/summaries/"],
    }
```

Versioned definitions of the view are to be saved at the path under `view_directory`, for example

```sql
-- assets/views/summaries/1_20230923193658_initial_definition.sql
    CREATE OR REPLACE VIEW summaries AS
      select 
        z.zip, z.zip_family_rating, z.zip_housing_rating, z.zip_school_rating, 
        n.nbd_name, n.nbd_percent_renting, n.vacancy_rate, 
        n.median_house_price, n.average_monthly_rent, 
        p.monthly_hoa_fee, p.square_footage, p.estimated_repair_cost, 
        p.year_built, p.tax_balance, p.total_finished_area, 
        p.bathrooms, p.garage, p.basement, p.annual_tax,
        a.id as auction_id, a.opening_bid, a.foreclosure_type, a.sale_type, a.deposit, a.first_date, a.second_date, a.should_bid,
        d.def_is_deceased, d.def_age, 
        -- CALCULATED FIELDS
        avg(ap.appraised_value) as avg_appraised_value,
        (avg(re.estimate) - p.monthly_hoa_fee) as adjusted_avg_rent_estimate,
        coalesce(sum(l.lien_amount), 0) as total_liens,
        string_agg(distinct ns."text", '; ') as property_notes,
        p.street || ', ' || p.city as address,
        (
          (12*(avg(re.estimate))) 
          - (12*(avg(re.estimate))*0.15) 
          - (12*(avg(re.estimate))*0.08) 
          - p.annual_tax 
          - 900 
          - (12*p.monthly_hoa_fee)
        ) as net_operating_income
    from zipcodes z 
    join neighborhoods n on n.zipcode_id = z.id 
    join properties p on n.id = p.neighborhood_id 
    join auctions a on a.id = p.auction_id
    left join notes ns on a.id = ns.auction_id
    join defendants d on a.id = d.auction_id 
    join appraisals ap on ap.property_id = p.id
    left join liens l on l.property_id = p.id
    join rent_estimates re on re.property_id = p.id
    group by
      z.zip, z.zip_family_rating, z.zip_housing_rating, z.zip_school_rating,
      n.nbd_name, n.nbd_percent_renting, n.vacancy_rate, 
      n.median_house_price, n.average_monthly_rent, 
      p.monthly_hoa_fee, p.square_footage, p.estimated_repair_cost, 
      p.year_built, p.tax_balance, p.total_finished_area, 
      p.bathrooms, p.garage, p.basement, p.annual_tax, p.street, p.city,
      a.id, a.opening_bid, a.foreclosure_type, a.sale_type, a.deposit, a.first_date, a.second_date, a.should_bid,
      d.def_is_deceased, d.def_age
    ;
```

You'll want to `use` a layer for managing migrations that involve a view, such as:

```elixir
defmodule MyProject.SummaryMigrator do
  defmacro __using__(opts) do

    [view_name: view_name, view_directory: view_directory] = 
      Application.get_env(:view_migrator, :views) 
      |> Map.get(:summaries)

    quote bind_quoted: [opts: opts, view_name: view_name, view_directory: view_directory] do

      use ViewMigrator,
       view_name:      view_name,
       view_directory: view_directory,
       current_view_version:  Keyword.fetch!(opts, :current_view_version),
       bumping_version?:      Keyword.get(opts, :bumping_version?, true)

    end
  end
end
```

2) Using the migrations

To create a new view (no current view, with the expectation that version 1 is in configured view directory):

```elixir
defmodule MyProject.Repo.Migrations.CreateSummaryView do
  use MyProject.SummaryMigrator, 
    current_view_version: nil

    create_view()
end
```


To re-define just the view. For example, the new definition might have another field from a base table
or a new calculated field. All the details are in the new version defined in version 2 of the `sql` file:


```elixir
defmodule MyProject.Repo.Migrations.AddFieldToSummary do
  use MyProject.SummaryMigrator,
    current_view_version: 1
  
  change_view()
end
```

To change a table that is used in a view, when changes to the view are *not* needed
The migration will not search for a version 3 of the `sql` view definition:

```elixir
defmodule MyProject.Repo.Migrations.ZipcodeZipNotNull do
  use MyProject.SummaryMigrator, 
    current_view_version: 2,
    bumping_version?: false
  
  change_with_view :up do
    alter table("zipcodes") do
      modify :zip, :string, null: false
    end
  end

  change_with_view :down do
    alter table("zipcodes") do
      modify :zip, :string, null: true
    end
  end
end
```

To change a table that is used in a view, when changes to the view *are* needed. 
Version 3 of the view would have the names of fields similarly updated:

```elixir
defmodule MyProject.Repo.Migrations.MakePercentFieldNameMoreSpecificToTable do
  use MyProject.SummaryMigrator, 
    current_view_version: 2

  change_with_view :up do
    rename table("zipcodes"), :percent_renting, to: :zip_percent_renting
  end

  change_with_view :down do
    rename table("zipcodes"), :zip_percent_renting, to: :percent_renting
  end
end
```

To drop the view:

```elixir
defmodule MyProject.Repo.Migrations.DropSummaryView do
  use MyProject.SummaryMigrator,
    current_view_version: 3

    drop_view()
end
```
