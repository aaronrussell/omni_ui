defmodule OmniUI.TreeFaker do
  @moduledoc false

  # Generates a static `OmniUI.Tree` for UI development.
  #
  # Main conversation (nodes 1–24, active path):
  #
  #   - t0: Simple greeting (nodes 1–2)
  #   - t1: Tool-calling turn — current_user + get_weather (nodes 3–8)
  #   - t2: Follow-up question, no tools (nodes 9–10)
  #   - t3: Multi-tool turn — search + fetch (nodes 11–16)
  #   - t4: Failed tool result, is_error: true (nodes 17–20)
  #   - t5: All typographical elements (nodes 21–22)
  #   - t6: Code blocks and mermaid diagram (nodes 23–24)
  #
  # Branches:
  #
  #   - Fork (nodes 25–28): branches from node 8 (end of weather turn).
  #     Node 25 is a sibling of node 9 — two user messages sharing the same parent.
  #
  #   - Regeneration (node 29): branches from node 9 (user "lunch spots" message).
  #     Node 29 is a sibling of node 10 — two assistant messages sharing the same parent.

  alias Omni.{Content, Usage}
  alias OmniUI.Tree

  @spec generate() :: Tree.t()
  def generate do
    %Tree{}
    |> t0_greeting()
    |> t1_tool_use()
    |> t2_followup()
    |> t3_multi_tool()
    |> t4_failed_tool()
    |> t5_typography()
    |> t6_code_and_mermaid()
    |> fork_after_weather()
    |> regen_lunch_spots()
  end

  # Turn 0: Simple greeting — user says hello, assistant responds
  defp t0_greeting(tree) do
    tree
    |> Tree.push(user_message("Hello! What can you help me with?"))
    |> Tree.push(
      assistant_message([
        %Content.Thinking{
          text:
            "The user is greeting me and asking what I can do. I should give a friendly overview of my capabilities."
        },
        %Content.Text{
          text:
            "Hi there! I'm an AI assistant that can help you with a variety of tasks:\n\n- **Answer questions** on a wide range of topics\n- **Look up information** using tools like search and user profiles\n- **Write and edit** text, code, and documents\n- **Analyze data** and help with problem-solving\n\nWhat would you like to work on?"
        }
      ]),
      %Usage{
        input_tokens: 45,
        output_tokens: 82,
        total_tokens: 127,
        input_cost: 0.0011,
        output_cost: 0.0041,
        total_cost: 0.0052
      }
    )
  end

  # Turn 1: Tool use — assistant calls current_user and get_weather
  defp t1_tool_use(tree) do
    tree
    |> Tree.push(user_message("What's the weather like where I am?"))
    # First assistant message — calls current_user tool
    |> Tree.push(
      assistant_message([
        %Content.Thinking{
          text:
            "The user wants weather info. I need to look up who they are first to get their location, then check the weather."
        },
        %Content.ToolUse{
          id: "tool_call_001",
          name: "current_user",
          input: %{}
        }
      ])
    )
    # Tool result comes back in a user message
    |> Tree.push(
      user_message([
        %Content.ToolResult{
          tool_use_id: "tool_call_001",
          name: "current_user",
          content: [
            %Content.Text{text: "{\"name\":\"John Smith\",\"location\":\"London, UK\"}"}
          ]
        }
      ])
    )
    # Second assistant message — calls get_weather
    |> Tree.push(
      assistant_message([
        %Content.ToolUse{
          id: "tool_call_002",
          name: "get_weather",
          input: %{"location" => "London, UK"}
        }
      ])
    )
    # Weather result
    |> Tree.push(
      user_message([
        %Content.ToolResult{
          tool_use_id: "tool_call_002",
          name: "get_weather",
          content: [
            %Content.Text{
              text: "{\"temp\":\"14°C\",\"condition\":\"Partly cloudy\",\"humidity\":\"72%\"}"
            }
          ]
        }
      ])
    )
    # Final assistant response
    |> Tree.push(
      assistant_message([
        %Content.Text{
          text:
            "Based on your profile, you're in **London, UK**. Here's the current weather:\n\n- **Temperature:** 14°C\n- **Condition:** Partly cloudy\n- **Humidity:** 72%\n\nNot bad for London! You might want a light jacket if you're heading out."
        }
      ]),
      %Usage{
        input_tokens: 320,
        output_tokens: 195,
        total_tokens: 515,
        input_cost: 0.008,
        output_cost: 0.0098,
        total_cost: 0.0178
      }
    )
  end

  # Turn 2: Simple follow-up (no tools)
  defp t2_followup(tree) do
    tree
    |> Tree.push(user_message("Thanks! Can you recommend some good lunch spots nearby?"))
    |> Tree.push(
      assistant_message([
        %Content.Text{
          text:
            "Here are some popular lunch spots in London:\n\n1. **Dishoom** — Bombay-inspired café. The bacon naan roll is legendary.\n2. **Padella** — Fresh pasta, reasonable prices, always a queue (worth it).\n3. **Borough Market** — Not a single restaurant, but dozens of street food stalls. Great for browsing.\n4. **Bao** — Taiwanese steamed buns. Small menu, everything is good.\n5. **The Palomar** — Jerusalem-style cooking in Soho. Sit at the bar if you can.\n\nWant me to look up directions or opening hours for any of these?"
        }
      ]),
      %Usage{
        input_tokens: 580,
        output_tokens: 145,
        total_tokens: 725,
        input_cost: 0.0145,
        output_cost: 0.0073,
        total_cost: 0.0218
      }
    )
  end

  # Turn 3: Multi-tool turn — search + fetch
  defp t3_multi_tool(tree) do
    tree
    |> Tree.push(user_message("Can you search for Dishoom's menu and tell me the prices?"))
    |> Tree.push(
      assistant_message([
        %Content.Thinking{
          text:
            "The user wants Dishoom's menu with prices. I'll search for it first, then fetch the page."
        },
        %Content.ToolUse{
          id: "tool_call_003",
          name: "search",
          input: %{"query" => "Dishoom London menu prices 2025"}
        }
      ])
    )
    |> Tree.push(
      user_message([
        %Content.ToolResult{
          tool_use_id: "tool_call_003",
          name: "search",
          content: [
            %Content.Text{
              text:
                "[{\"title\":\"Dishoom Menu & Prices\",\"url\":\"https://www.dishoom.com/menus/\",\"snippet\":\"View our full menu including breakfast, lunch and dinner...\"}]"
            }
          ]
        }
      ])
    )
    |> Tree.push(
      assistant_message([
        %Content.ToolUse{
          id: "tool_call_004",
          name: "fetch",
          input: %{"url" => "https://www.dishoom.com/menus/"}
        }
      ])
    )
    |> Tree.push(
      user_message([
        %Content.ToolResult{
          tool_use_id: "tool_call_004",
          name: "fetch",
          content: [
            %Content.Text{
              text:
                "Bacon Naan Roll £8.90 | House Black Daal £7.50 | Chicken Ruby £13.90 | Lamb Biryani £16.50 | Gunpowder Potatoes £6.50 | Dishoom Calamari £9.90"
            }
          ]
        }
      ])
    )
    |> Tree.push(
      assistant_message([
        %Content.Text{
          text:
            "Here are some highlights from **Dishoom's menu**:\n\n| Dish | Price |\n|------|-------|\n| Bacon Naan Roll | £8.90 |\n| House Black Daal | £7.50 |\n| Chicken Ruby | £13.90 |\n| Lamb Biryani | £16.50 |\n| Gunpowder Potatoes | £6.50 |\n| Dishoom Calamari | £9.90 |\n\nThe **House Black Daal** is their signature dish — slow-cooked for 24 hours. Highly recommend it alongside some naan. The Bacon Naan Roll is breakfast only, so time your visit accordingly!"
        }
      ]),
      %Usage{
        input_tokens: 890,
        output_tokens: 210,
        total_tokens: 1100,
        input_cost: 0.0223,
        output_cost: 0.0105,
        total_cost: 0.0328
      }
    )
  end

  # Turn 4: Failed tool — database query tool returns an error
  defp t4_failed_tool(tree) do
    tree
    |> Tree.push(user_message("Can you look up my reservation history at Dishoom?"))
    |> Tree.push(
      assistant_message([
        %Content.Thinking{
          text:
            "The user wants their reservation history. I'll query the reservations database for their profile."
        },
        %Content.ToolUse{
          id: "tool_call_006",
          name: "query_database",
          input: %{
            "table" => "reservations",
            "filter" => %{"user_id" => "usr_42", "restaurant" => "Dishoom"},
            "order_by" => "date DESC"
          }
        }
      ])
    )
    |> Tree.push(
      user_message([
        %Content.ToolResult{
          tool_use_id: "tool_call_006",
          name: "query_database",
          is_error: true,
          content: [
            %Content.Text{
              text:
                "ConnectionError: could not connect to database server at \"db-primary.internal:5432\" — connection refused. The server may not be running or may not be accepting TCP/IP connections on the specified port."
            }
          ]
        }
      ])
    )
    |> Tree.push(
      assistant_message([
        %Content.Text{
          text:
            "I'm sorry, I wasn't able to look up your reservation history — the database is currently unavailable. This is likely a temporary issue on our end.\n\nYou can try again in a few minutes, or if you need the information right away, you could check your confirmation emails for past Dishoom bookings."
        }
      ]),
      %Usage{
        input_tokens: 720,
        output_tokens: 95,
        total_tokens: 815,
        input_cost: 0.018,
        output_cost: 0.0048,
        total_cost: 0.0228
      }
    )
  end

  # Turn 5: All typographical elements — headings, paragraphs, lists, blockquotes, links
  defp t5_typography(tree) do
    tree
    |> Tree.push(
      user_message(
        "Give me a comprehensive overview of London's food scene — I want the full picture."
      )
    )
    |> Tree.push(
      assistant_message([
        %Content.Text{
          text: """
          # London's Food Scene: A Complete Guide

          London has become one of the world's great food cities. What was once mocked for bland cuisine now rivals Paris, Tokyo, and New York in diversity and quality.

          ## The History

          The transformation began in the 1990s with the rise of **Modern British** cooking. Chefs like Fergus Henderson championed nose-to-tail dining, proving British ingredients could shine.

          ### Key Milestones

          - **1994** — Fergus Henderson opens St. JOHN in Smithfield
          - **2001** — Borough Market reopens as a public food market
          - **2012** — The Olympics put London street food on the world stage
          - **2020s** — Post-pandemic boom in neighbourhood restaurants

          ## What Makes It Special

          London's strength is its *extraordinary diversity*. Within a single mile you can find:

          1. **Brick Lane** — Bangladeshi curry houses dating back decades
          2. **Chinatown** — Cantonese roast meats and dim sum
          3. **Edgware Road** — Lebanese and Middle Eastern grill rooms
          4. **Brixton Market** — Caribbean, West African, and Colombian street food

          ### The Market Scene

          Markets are the beating heart of London food culture:

          - **Borough Market** — The granddaddy. Cheese, charcuterie, pastries, everything
          - **Broadway Market** — Saturday morning favourite in Hackney
          - **Maltby Street** — The insider's Borough, tucked under railway arches
            - Great for: artisan producers, smaller crowds
            - Don't miss: The cheese toastie at Kappacasein

          ## Dining Tiers

          #### Fine Dining

          Michelin stars are well-represented, but London fine dining has a refreshing lack of stuffiness compared to Paris.

          ##### Notable Spots

          Places like The Clove Club and Brat have redefined what high-end British food looks like.

          ###### Price Expectations

          Expect £100–200 per person at the top tier, though set lunch menus can be surprisingly affordable at £35–50.

          ## What the Critics Say

          > "London is now the most exciting food city in Europe — not because of any single cuisine, but because every cuisine in the world is represented, often at an extraordinarily high level."
          >
          > — *Jay Rayner, The Observer*

          > "The best meal I had last year wasn't in Copenhagen or Lima. It was a £12 plate of jollof rice in Peckham."
          >
          > — *Food & Travel Magazine*

          ## Getting Started

          If you're new to London dining, here are some resources:

          - [Time Out London Food](https://www.timeout.com/london/food-drink) — Best for trending openings
          - [Eater London](https://london.eater.com) — Neighbourhood guides and maps
          - [Hot Dinners](https://www.hotdinners.com) — News on what's opening where

          For booking popular spots, **reserve 2–4 weeks ahead** on [OpenTable](https://www.opentable.co.uk) or check for walk-in availability on the day.

          ---

          Want me to narrow this down to a specific neighbourhood or cuisine?\
          """
        }
      ]),
      %Usage{
        input_tokens: 950,
        output_tokens: 580,
        total_tokens: 1530,
        input_cost: 0.0238,
        output_cost: 0.029,
        total_cost: 0.0528
      }
    )
  end

  # Turn 6: Code blocks and mermaid diagram
  defp t6_code_and_mermaid(tree) do
    tree
    |> Tree.push(
      user_message(
        "I'm building a restaurant recommendation app. Can you show me how to model this in Elixir and diagram the architecture?"
      )
    )
    |> Tree.push(
      assistant_message([
        %Content.Thinking{
          text:
            "The user wants to see Elixir code for a restaurant recommendation system plus an architecture diagram. I'll show schema modules, a recommendation function with pattern matching, and a mermaid diagram of the system."
        },
        %Content.Text{
          text: """
          Great idea! Here's a starting point for modelling this in Elixir.

          ## Data Schemas

          First, define your core schemas with `Ecto`:

          ```elixir
          defmodule FoodFinder.Restaurants.Restaurant do
            use Ecto.Schema
            import Ecto.Changeset

            schema "restaurants" do
              field :name, :string
              field :cuisine, :string
              field :price_tier, Ecto.Enum, values: [:budget, :mid, :fine]
              field :rating, :float
              field :location, Geo.PostGIS.Geometry

              has_many :reviews, FoodFinder.Reviews.Review
              many_to_many :tags, FoodFinder.Tags.Tag, join_through: "restaurant_tags"

              timestamps()
            end

            def changeset(restaurant, attrs) do
              restaurant
              |> cast(attrs, [:name, :cuisine, :price_tier, :rating, :location])
              |> validate_required([:name, :cuisine, :price_tier])
              |> validate_number(:rating, greater_than: 0, less_than_or_equal_to: 5)
            end
          end
          ```

          ## Recommendation Engine

          Use pattern matching and `Enum` to score and rank results:

          ```elixir
          defmodule FoodFinder.Recommendations do
            @moduledoc "Scores and ranks restaurant recommendations."

            alias FoodFinder.Restaurants.Restaurant

            @type preference :: %{
                    cuisine: String.t() | nil,
                    price_tier: atom() | nil,
                    max_distance_km: float()
                  }

            @spec recommend(list(Restaurant.t()), preference()) :: list(Restaurant.t())
            def recommend(restaurants, preferences) do
              restaurants
              |> Enum.map(&{&1, score(&1, preferences)})
              |> Enum.filter(fn {_r, score} -> score > 0 end)
              |> Enum.sort_by(fn {_r, score} -> score end, :desc)
              |> Enum.map(fn {r, _score} -> r end)
              |> Enum.take(10)
            end

            defp score(%Restaurant{} = r, prefs) do
              base = r.rating * 20

              cuisine_bonus = if prefs[:cuisine] == r.cuisine, do: 30, else: 0
              price_match = if prefs[:price_tier] == r.price_tier, do: 20, else: 0

              base + cuisine_bonus + price_match
            end
          end
          ```

          You'd call it like this in `iex`:

          ```elixir
          iex> prefs = %{cuisine: "Japanese", price_tier: :mid, max_distance_km: 3.0}
          iex> FoodFinder.Recommendations.recommend(restaurants, prefs)
          [%Restaurant{name: "Kanada-Ya", cuisine: "Japanese", ...}, ...]
          ```

          ## System Architecture

          Here's how the components fit together:

          ```mermaid
          graph TD
              A[Phoenix LiveView UI] -->|user preferences| B[Recommendation Engine]
              B -->|scored results| A
              B -->|queries| C[(PostgreSQL + PostGIS)]
              C -->|restaurant data| B

              A -->|search input| D[Search Service]
              D -->|full-text search| C

              E[Review Ingestion] -->|new reviews| C
              E -->|sentiment analysis| F[ML Pipeline]
              F -->|sentiment scores| C

              G[External APIs] -->|Google Places<br/>TripAdvisor| E

              style A fill:#4f46e5,color:#fff
              style B fill:#059669,color:#fff
              style C fill:#d97706,color:#fff
              style F fill:#dc2626,color:#fff
          ```

          ## Running It Locally

          To get this up and running, you'd set up the project with:

          ```bash
          mix phx.new food_finder
          cd food_finder
          mix ecto.create
          mix phx.gen.schema Restaurants.Restaurant restaurants \\
            name:string cuisine:string price_tier:enum:budget:mid:fine rating:float
          mix ecto.migrate
          ```

          The `Geo.PostGIS` library handles spatial queries — add `{:geo_postgis, "~> 3.4"}` to your `mix.exs` deps.

          Want me to flesh out any of these parts further?\
          """
        }
      ]),
      %Usage{
        input_tokens: 1680,
        output_tokens: 820,
        total_tokens: 2500,
        input_cost: 0.042,
        output_cost: 0.041,
        total_cost: 0.083
      }
    )
  end

  # Fork: alternative user follow-up after the weather turn.
  # Navigates to node 8 (end of t1), pushes a different user question (node 25)
  # that becomes a sibling of node 9. Simulates the user editing their prompt.
  defp fork_after_weather(tree) do
    main_head = Tree.head(tree)
    {:ok, tree} = Tree.navigate(tree, 8)

    tree =
      tree
      |> Tree.push(user_message("Actually, is it going to rain later today?"))
      |> Tree.push(
        assistant_message([
          %Content.ToolUse{
            id: "tool_call_005",
            name: "get_weather",
            input: %{"location" => "London, UK", "forecast" => true}
          }
        ])
      )
      |> Tree.push(
        user_message([
          %Content.ToolResult{
            tool_use_id: "tool_call_005",
            name: "get_weather",
            content: [
              %Content.Text{
                text:
                  "{\"forecast\":[{\"time\":\"14:00\",\"condition\":\"Cloudy\",\"rain_chance\":\"30%\"},{\"time\":\"17:00\",\"condition\":\"Light rain\",\"rain_chance\":\"75%\"},{\"time\":\"20:00\",\"condition\":\"Rain\",\"rain_chance\":\"90%\"}]}"
              }
            ]
          }
        ])
      )
      |> Tree.push(
        assistant_message([
          %Content.Text{
            text:
              "Looks like rain is moving in later today:\n\n- **2:00 PM** — Cloudy, 30% chance of rain\n- **5:00 PM** — Light rain likely (75%)\n- **8:00 PM** — Rain expected (90%)\n\nIf you're planning to be out this evening, definitely bring an umbrella!"
          }
        ]),
        %Usage{
          input_tokens: 610,
          output_tokens: 120,
          total_tokens: 730,
          input_cost: 0.0153,
          output_cost: 0.006,
          total_cost: 0.0213
        }
      )

    {:ok, tree} = Tree.navigate(tree, main_head)
    tree
  end

  # Regeneration: alternative assistant response to the lunch spots question.
  # Navigates to node 9 (user message of t2), pushes a different response (node 29)
  # that becomes a sibling of node 10. Simulates the user regenerating a response.
  defp regen_lunch_spots(tree) do
    main_head = Tree.head(tree)
    {:ok, tree} = Tree.navigate(tree, 9)

    tree =
      Tree.push(
        tree,
        assistant_message([
          %Content.Text{
            text:
              "Here are some alternative London lunch picks:\n\n1. **Koya** — Handmade udon in Soho. The cold udon with dipping broth is perfect.\n2. **Hoppers** — Sri Lankan street food. Get the egg hopper with seeni sambol.\n3. **Rochelle Canteen** — Hidden behind a school wall in Shoreditch. Simple British classics.\n4. **Morito** — Moorish small plates on Exmouth Market. Everything is shareable.\n5. **Lahore Kebab House** — Whitechapel institution. Huge portions, tiny prices.\n\nA different vibe from the first list — want me to compare any of these?"
          }
        ]),
        %Usage{
          input_tokens: 580,
          output_tokens: 138,
          total_tokens: 718,
          input_cost: 0.0145,
          output_cost: 0.0069,
          total_cost: 0.0214
        }
      )

    {:ok, tree} = Tree.navigate(tree, main_head)
    tree
  end

  # Helpers

  defp user_message(text) when is_binary(text) do
    Omni.message(text)
  end

  defp user_message(content) when is_list(content) do
    Omni.message(role: :user, content: content)
  end

  defp assistant_message(content) when is_list(content) do
    Omni.message(role: :assistant, content: content)
  end
end
