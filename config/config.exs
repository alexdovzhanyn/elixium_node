use Mix.Config

config :logger, backends: [:console, {LoggerFileBackend, :info}]

config :logger, :info,
  path: "./log/info.log",
  level: :info

if File.exists?("config/#{Mix.env}.exs") do
  import_config "#{Mix.env}.exs"
end
