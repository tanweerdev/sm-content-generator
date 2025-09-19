# Social Media Content Generator - Setup Guide

This application transforms meeting transcripts into engaging social media content using AI.

## Features

- **Google Calendar Integration**: Connect multiple Google accounts and sync calendar events
- **AI Notetaker**: Automatically join meetings and create transcripts using Recall.ai
- **Content Generation**: Use OpenAI to generate professional social media posts from meeting insights
- **Social Media Posting**: Post generated content to LinkedIn and other platforms
- **Meeting Management**: Toggle AI notetaker on/off for individual calendar events

## Prerequisites

- Elixir 1.15+
- PostgreSQL
- Google Cloud Console access
- OpenAI API access
- Recall.ai account

## Setup Instructions

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd cgenerator
mix deps.get
```

### 2. Database Setup

```bash
mix ecto.create
mix ecto.migrate
```

### 3. Environment Variables

Copy the example environment file:

```bash
cp .env.example .env
```

Configure the following environment variables:

### 4. Google OAuth Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable the following APIs:
   - Google Calendar API
   - Google+ API (for user info)
4. Create OAuth 2.0 credentials:
   - Application type: Web application
   - Authorized redirect URIs: `http://localhost:4000/auth/google/callback`
5. Add `tanweerdev@gmail.com` as a test user in OAuth consent screen
6. Copy Client ID and Client Secret to your `.env` file

### 5. OpenAI Setup

1. Get API key from [OpenAI Platform](https://platform.openai.com/)
2. Add to `OPENAI_API_KEY` in `.env`

### 6. Recall.ai Setup

1. Create account at [Recall.ai](https://www.recall.ai/)
2. Follow [quickstart guide](https://docs.recall.ai/docs/quickstart)
3. Get API token and add to `RECALL_AI_API_TOKEN` in `.env`
4. Configure webhook URL: `http://your-domain.com/webhooks/recall`

### 7. Start the Application

```bash
mix phx.server
```

Visit `http://localhost:4000`

## Usage

1. **Sign in**: Click "Sign in with Google" on the homepage
2. **Connect Calendar**: Your Google Calendar will be automatically synced
3. **Enable Notetaker**: Toggle the AI notetaker on for meetings you want transcribed
4. **Review Content**: Generated social media posts will appear in your dashboard
5. **Edit & Post**: Review, edit, and publish content to social media platforms

## Key Files

- **Authentication**: `lib/smg_web/controllers/auth_controller.ex`
- **Dashboard**: `lib/smg_web/live/dashboard_live.ex`
- **Google Calendar**: `lib/smg/integrations/google_calendar.ex`
- **Recall.ai**: `lib/smg/integrations/recall_ai.ex`
- **AI Content**: `lib/smg/ai/content_generator.ex`
- **Social Posting**: `lib/smg/services/social_media_poster.ex`

## API Integrations

### Google Calendar API
- Fetches calendar events
- Extracts meeting links (Zoom, Google Meet, Teams)
- Syncs event data to local database

### Recall.ai API
- Schedules AI notetaker for meetings
- Receives webhook notifications for transcript completion
- Downloads and processes meeting transcripts

### OpenAI API
- Generates social media content from transcripts
- Supports multiple platforms (LinkedIn, Twitter)
- Customizable prompts for different content styles

## Database Schema

- **Users**: User accounts and profile information
- **GoogleAccounts**: OAuth tokens and Google account details
- **CalendarEvents**: Meeting data and notetaker settings
- **SocialPosts**: Generated content and posting status

## Security Notes

- OAuth tokens are encrypted in database
- Webhook endpoints are secured
- User data is isolated by account
- No sensitive meeting content is logged

## Development

Run tests:
```bash
mix test
```

Format code:
```bash
mix format
```

## Production Deployment

1. Set production environment variables
2. Configure webhook URLs for Recall.ai
3. Set up SSL certificates
4. Configure domain for OAuth redirects
5. Deploy using your preferred platform (Fly.io, Heroku, etc.)

## Troubleshooting

### Google OAuth Issues
- Verify redirect URIs match exactly
- Check OAuth consent screen settings
- Ensure test users are added

### Recall.ai Issues
- Verify API token is correct
- Check webhook URL is accessible
- Ensure meeting links are valid

### Content Generation Issues
- Verify OpenAI API key
- Check API usage limits
- Review error logs for specific issues

## Support

For issues or questions, check the logs:
```bash
tail -f _build/dev/lib/cgenerator/ebin/cgenerator.log
```