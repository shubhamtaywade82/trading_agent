# frozen_string_literal: true

require_relative "lib/trading_agent/version"

Gem::Specification.new do |spec|
  spec.name = "trading_agent"
  spec.version = TradingAgent::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "Autonomous trading agent framework using Ollama LLM for reasoning."
  spec.description = "A production-grade trading framework that combines deterministic risk management with LLM-powered market analysis."
  spec.homepage = "https://github.com/shubhamtaywade82/ollama_agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "exe/*", "LICENSE.txt", "README.md"]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ollama_agent", ">= 1.0.0"
  spec.add_dependency "binance-connector-ruby", "~> 1.7"
  spec.add_dependency "async", "~> 2.10"
  spec.add_dependency "concurrent-ruby", "~> 1.2"
  spec.add_dependency "dry-schema", "~> 1.13"
  spec.add_dependency "dry-validation", "~> 1.10"
  spec.add_dependency "dry-events", "~> 1.0"
  spec.add_dependency "oj", "~> 3.16"
  spec.add_dependency "http", "~> 5.1"
  spec.add_dependency "semantic_logger", "~> 4.15"
  spec.add_dependency "websocket-eventmachine-client", "~> 1.3"

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
