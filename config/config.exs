use Mix.Config

config :logger,
  backends: [:console, {LoggerFileBackend, :info}],
  level: :info
