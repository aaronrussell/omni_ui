import Config

# AgentLive requires a store to compile — it calls load_session/1, save_tree/2,
# etc. which are only injected by `use OmniUI` when a store is configured.
# Without this, `mix compile` at the library root produces Dialyzer warnings
# (unreachable clauses) or outright compilation errors.
config :omni, OmniUI.Store, adapter: OmniUI.Store.FileSystem
