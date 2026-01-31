# MGE Statistics Project

## Project Structure
```
web/
├── stats_mge.php          # Main statistics page
├── css/
│   └── styles.css         # Stylesheet
├── js/
├── images/
├── auth/
│   ├── steam_auth.php     # Steam authentication functions
│   └── steam_handler.php  # Steam authentication handler
├── includes/
│   └── helpers.php        # Helper functions
├── config/
│   └── secure_config_statstf2.php # Secure configuration
├── LightOpenID.php        # OpenID library
└── .htaccess              # Security configurations
```

## Setup Instructions

1. Update the configuration file `config/secure_config_statstf2.php` with your database credentials and Steam API key.
2. Ensure your web server has the necessary permissions to access the files.
3. Make sure the config directory is not accessible via web browser (protected by .htaccess).

## Security Notes

- The config directory is protected from direct web access via .htaccess rules
- Database credentials and API keys are stored in a secure configuration file outside the web root conceptually
- Input validation and sanitization are implemented throughout the application