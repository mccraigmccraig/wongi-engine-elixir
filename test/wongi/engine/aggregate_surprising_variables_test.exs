defmodule Wongi.Engine.AggregateSurprisingVariablesTest do
  use Wongi.TestCase

  describe "surprising variables after aggregation" do
    test "non-partition variables accessed after aggregation give arbitrary results" do
      # Scenario: Jupiter has 4 moons, each with a mass. We want to compute
      # the total moon mass orbiting Jupiter, then record that total against
      # each individual moon (so each moon "knows" the total mass of its
      # sibling system).
      #
      # The rule:
      # 1. Match (moon, :orbits, planet) and (moon, :mass, moon_mass)
      # 2. Aggregate sum of moon_mass, partitioned by planet
      # 3. Generate (moon, :total_moon_mass, total) for each moon
      #
      # The problem: after the aggregate (partitioned by :planet), the
      # :moon variable is no longer meaningful — it varied across the
      # aggregation inputs. But Token.fetch/2 walks parent tokens and
      # returns an arbitrary :moon value, so gen() silently picks ONE
      # moon and only generates a fact for that moon.

      rete =
        new()
        |> compile(
          rule(
            forall: [
              has(var(:moon), :orbits, var(:planet)),
              has(var(:moon), :mass, var(:moon_mass)),
              aggregate(&sum/1, :total_moon_mass,
                over: :moon_mass,
                partition: :planet
              )
            ],
            do: [
              # This is the problematic part: :moon was not in the partition
              # or aggregate output, so its value after aggregation is
              # arbitrary. The gen will use whichever :moon value
              # Token.fetch happens to find first in the parent token list.
              gen(var(:moon), :total_moon_mass, var(:total_moon_mass))
            ]
          )
        )

      # Jupiter has 4 Galilean moons
      rete =
        rete
        |> assert(:io, :orbits, :jupiter)
        |> assert(:europa, :orbits, :jupiter)
        |> assert(:ganymede, :orbits, :jupiter)
        |> assert(:callisto, :orbits, :jupiter)
        |> assert(:io, :mass, 894)
        |> assert(:europa, :mass, 480)
        |> assert(:ganymede, :mass, 1482)
        |> assert(:callisto, :mass, 1076)

      # total_moon_mass for jupiter = 894 + 480 + 1482 + 1076 = 3932
      #
      # A naive user would expect 4 facts:
      #   (:io,       :total_moon_mass, 3932)
      #   (:europa,   :total_moon_mass, 3932)
      #   (:ganymede, :total_moon_mass, 3932)
      #   (:callisto, :total_moon_mass, 3932)
      #
      # But because :moon is a surprising variable after aggregation,
      # we get only ONE fact — for whichever :moon value Token.fetch
      # happens to find first when walking the parent token list.

      results =
        rete
        |> select(:_, :total_moon_mass, :_)
        |> Enum.to_list()

      total_moon_mass_subjects =
        results
        |> Enum.map(& &1.subject)
        |> Enum.sort()

      all_moons = [:callisto, :europa, :ganymede, :io]

      # BUG: we only get one generated fact instead of the four a user
      # would expect. The :moon variable after aggregation resolved to
      # an arbitrary single value from the aggregation inputs.
      assert length(results) == 1
      assert [single_moon] = total_moon_mass_subjects
      assert single_moon in all_moons

      # The mass is correct for the single fact that was generated
      assert hd(results).object == 3932

      # What we'd actually WANT (if surprising variables were prevented):
      # assert length(results) == 4
      # assert total_moon_mass_subjects == all_moons
    end
  end
end
