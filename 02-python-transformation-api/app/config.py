from pydantic_settings import BaseSettings, SettingsConfigDict

class ApplicationSettings(BaseSettings):
    """
    Centralized configuration engine for the enterprise transformation layer.
    Automatically merges operating system environment variables with local config overrides.
    """
    # Application Deployment Parameters
    APP_TITLE: str = "Enterprise Integration Transformation API"
    APP_VERSION: str = "1.0.0"
    
    # Network Layer Settings
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8082
    
    # Inbound security key contract. Required: supplied by the environment or a local .env file.
    API_SECURITY_TOKEN: str

    # Instructs Pydantic to read configuration from a local file if available
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

# Initialize a singleton instance of our settings model for the entire app package
settings = ApplicationSettings()
