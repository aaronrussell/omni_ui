defmodule OmniUI.FakeTree do
  @moduledoc """
  Generates a static `Omni.MessageTree` for UI development.

  Usage:

      {:ok, agent} = Omni.Agent.start_link(
        model: {:anthropic, "claude-haiku-4-5"},
        tree: OmniUI.FakeTree.generate()
      )

      tree = Omni.Agent.get_state(agent, :tree)

  The tree contains 5 turns on the active path:

    - Turn 0: Simple greeting (no tools)
    - Turn 1: Tool-calling turn (current_user lookup + weather check)
    - Turn 2: Follow-up question (no tools)
    - Turn 3: Multi-tool turn (search + fetch)
    - Turn 4: Branched — a sibling of turn 2 (alternate follow-up)

  Active path: [0, 1, 2, 3]. Turn 4 branches from turn 1 (sibling of turn 2).
  """

  alias Omni.{Content, MessageTree, Turn, Usage}

  @spec generate() :: MessageTree.t()
  def generate do
    turns = %{
      0 => turn_0_greeting(),
      1 => turn_1_tool_use(),
      2 => turn_2_followup(),
      3 => turn_3_multi_tool(),
      4 => turn_4_branch()
    }

    %MessageTree{
      turns: turns,
      active_path: [0, 1, 2, 3]
    }
  end

  # Turn 0: Simple greeting — user says hello, assistant responds
  defp turn_0_greeting do
    Turn.new(
      id: 0,
      parent: nil,
      messages: [
        user_message("Hello! What can you help me with?"),
        assistant_message([
          %Content.Thinking{
            text:
              "The user is greeting me and asking what I can do. I should give a friendly overview of my capabilities."
          },
          %Content.Text{
            text:
              "Hi there! I'm an AI assistant that can help you with a variety of tasks:\n\n- **Answer questions** on a wide range of topics\n- **Look up information** using tools like search and user profiles\n- **Write and edit** text, code, and documents\n- **Analyze data** and help with problem-solving\n\nWhat would you like to work on?"
          }
        ])
      ],
      usage: %Usage{
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
  defp turn_1_tool_use do
    Turn.new(
      id: 1,
      parent: 0,
      messages: [
        user_message("What's the weather like where I am?"),
        # First assistant message — calls current_user tool
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
        ]),
        # Tool result comes back in a user message
        user_message([
          %Content.ToolResult{
            tool_use_id: "tool_call_001",
            name: "current_user",
            content: [
              %Content.Text{text: "{\"name\":\"John Smith\",\"location\":\"London, UK\"}"}
            ]
          }
        ]),
        # Second assistant message — calls get_weather
        assistant_message([
          %Content.ToolUse{
            id: "tool_call_002",
            name: "get_weather",
            input: %{"location" => "London, UK"}
          }
        ]),
        # Weather result
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
        ]),
        # Final assistant response
        assistant_message([
          %Content.Text{
            text:
              "Based on your profile, you're in **London, UK**. Here's the current weather:\n\n- **Temperature:** 14°C\n- **Condition:** Partly cloudy\n- **Humidity:** 72%\n\nNot bad for London! You might want a light jacket if you're heading out."
          }
        ])
      ],
      usage: %Usage{
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
  defp turn_2_followup do
    Turn.new(
      id: 2,
      parent: 1,
      messages: [
        user_message("Thanks! Can you recommend some good lunch spots nearby?"),
        assistant_message([
          %Content.Text{
            text:
              "Here are some popular lunch spots in London:\n\n1. **Dishoom** — Bombay-inspired café. The bacon naan roll is legendary.\n2. **Padella** — Fresh pasta, reasonable prices, always a queue (worth it).\n3. **Borough Market** — Not a single restaurant, but dozens of street food stalls. Great for browsing.\n4. **Bao** — Taiwanese steamed buns. Small menu, everything is good.\n5. **The Palomar** — Jerusalem-style cooking in Soho. Sit at the bar if you can.\n\nWant me to look up directions or opening hours for any of these?"
          }
        ])
      ],
      usage: %Usage{
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
  defp turn_3_multi_tool do
    Turn.new(
      id: 3,
      parent: 2,
      messages: [
        user_message("Can you search for Dishoom's menu and tell me the prices?"),
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
        ]),
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
        ]),
        assistant_message([
          %Content.ToolUse{
            id: "tool_call_004",
            name: "fetch",
            input: %{"url" => "https://www.dishoom.com/menus/"}
          }
        ]),
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
        ]),
        assistant_message([
          %Content.Text{
            text:
              "Here are some highlights from **Dishoom's menu**:\n\n| Dish | Price |\n|------|-------|\n| Bacon Naan Roll | £8.90 |\n| House Black Daal | £7.50 |\n| Chicken Ruby | £13.90 |\n| Lamb Biryani | £16.50 |\n| Gunpowder Potatoes | £6.50 |\n| Dishoom Calamari | £9.90 |\n\nThe **House Black Daal** is their signature dish — slow-cooked for 24 hours. Highly recommend it alongside some naan. The Bacon Naan Roll is breakfast only, so time your visit accordingly!"
          }
        ])
      ],
      usage: %Usage{
        input_tokens: 890,
        output_tokens: 210,
        total_tokens: 1100,
        input_cost: 0.0223,
        output_cost: 0.0105,
        total_cost: 0.0328
      }
    )
  end

  # Turn 4: Branch — sibling of turn 2 (different follow-up to the weather response)
  # This turn shares parent 1 with turn 2, creating a branch
  defp turn_4_branch do
    Turn.new(
      id: 4,
      parent: 1,
      messages: [
        user_message("Actually, is it going to rain later today?"),
        assistant_message([
          %Content.ToolUse{
            id: "tool_call_005",
            name: "get_weather",
            input: %{"location" => "London, UK", "forecast" => true}
          }
        ]),
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
        ]),
        assistant_message([
          %Content.Text{
            text:
              "Looks like rain is moving in later today:\n\n- **2:00 PM** — Cloudy, 30% chance of rain\n- **5:00 PM** — Light rain likely (75%)\n- **8:00 PM** — Rain expected (90%)\n\nIf you're planning to be out this evening, definitely bring an umbrella!"
          }
        ])
      ],
      usage: %Usage{
        input_tokens: 610,
        output_tokens: 120,
        total_tokens: 730,
        input_cost: 0.0153,
        output_cost: 0.006,
        total_cost: 0.0213
      }
    )
  end

  # Helpers

  defp user_message(text) when is_binary(text) do
    Omni.Message.new(role: :user, content: text)
  end

  defp user_message(content) when is_list(content) do
    Omni.Message.new(role: :user, content: content)
  end

  defp assistant_message(content) when is_list(content) do
    Omni.Message.new(role: :assistant, content: content)
  end
end
