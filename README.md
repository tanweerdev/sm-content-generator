# Post-Meeting Social Media Content Generator

A Phoenix LiveView application that automatically generates social media content from meeting transcripts using AI. Advisors can connect their Google Calendar, have AI notetakers attend meetings via Recall.ai, and generate professional social media posts from the transcripts.

## Features

### ✅ Implemented Features

- **Google OAuth Integration**: Login with Google and connect multiple Google accounts
- **Google Calendar Sync**: Automatically sync calendar events from all connected accounts
- **Meeting Dashboard**: View upcoming and past meetings with intuitive interface
- **AI Notetaker Toggle**: Enable/disable AI notetaker for individual meetings
- **Recall.ai Integration**: Automatically send bots to meetings with Zoom/Meet/Teams links
- **Bot Status Polling**: Real-time monitoring of meeting bots and transcription status
- **Transcript Management**: Download and view full meeting transcripts
- **AI Content Generation**: Generate social media posts from meeting transcripts using OpenAI
- **Multi-Platform Support**: Create content optimized for LinkedIn and Twitter
- **Social Media Posting**: Edit and publish generated content to social platforms
- **Follow-up Email Generation**: AI-generated professional follow-up emails based on meeting content
- **Meeting Detail Views**: Comprehensive meeting details with multiple tabs
- **Platform Detection**: Automatic detection of Zoom, Google Meet, and Microsoft Teams links

### 🔧 Core Components

- **Dashboard**: Main interface showing upcoming events, connected accounts, and generated content
- **Meetings List**: Filterable list of past meetings with status indicators
- **Meeting Details**: Individual meeting view with transcript, social posts, and email generation
- **Social Post Editor**: Edit and publish AI-generated social media content
- **Real-time Updates**: Live status updates for transcription and content generation

## Setup Instructions

### Prerequisites

- Elixir 1.15+
- Phoenix 1.8+
- PostgreSQL
- Node.js (for assets)

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd sm-content-generator
mix deps.get
npm install --prefix assets
```

### 2. Database Setup

```bash
mix ecto.setup
```

### 3. Environment Configuration

Copy the `.env` file and configure the following:

#### Required API Keys

1. **Google OAuth Setup**:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or use existing: `sm-content-generator-472615`
   - Enable Google Calendar API
   - Create OAuth 2.0 credentials
   - Add `tanweerdev@gmail.com` as a test user in OAuth consent screen
   - The credentials are already configured in `.env`

2. **Recall.ai API**:
   - Create a free account at [Recall.ai](https://www.recall.ai/)
   - Get your API token from the dashboard
   - Update `RECALL_AI_API_TOKEN` in `.env`

3. **OpenAI API** (optional for AI features):
   - Get API key from [OpenAI](https://platform.openai.com/)
   - Update `OPENAI_API_KEY` in `.env`

#### Current Configuration
The application is pre-configured with Google OAuth credentials. You only need to:
- Add `tanweerdev@gmail.com` as a test user in Google Console
- Add your Recall.ai API token
- Add your OpenAI API key (optional)

### 4. Run the Application

```bash
source .env  # Load environment variables
mix phx.server
```

Visit `http://localhost:4000` to start using the application.

## Usage Guide

### 1. Initial Setup
1. Visit the homepage and click "Login with Google"
2. Authorize the application to access your Google Calendar
3. You'll be redirected to the dashboard

### 2. Connect Additional Google Accounts
- Click "Connect Google Account" to add more accounts
- All connected accounts' calendars will be synced

### 3. Enable AI Notetaker for Meetings
1. View upcoming events on the dashboard
2. Toggle the "AI Notetaker" checkbox for meetings you want to record
3. The system will automatically detect meeting links (Zoom, Meet, Teams)
4. Bots will join meetings a few minutes before they start

### 4. View Meeting Results
1. Navigate to "View All Meetings" to see past meetings
2. Filter by meetings with transcripts or social content
3. Click "View Details" to see full meeting information

### 5. Generate and Publish Content
1. Open a meeting with a completed transcript
2. Click "Generate Social Content" to create posts
3. Edit the generated content as needed
4. Publish to your social media platforms

### 6. Follow-up Emails
1. In the meeting details, switch to the "Follow-up Email" tab
2. Click "Generate Email" to create a professional summary
3. Copy and use the generated email for follow-ups

## Technical Architecture

### Backend
- **Phoenix Framework**: Web framework and LiveView for real-time updates
- **Ecto**: Database ORM with PostgreSQL
- **Tesla**: HTTP client for API integrations
- **Ueberauth**: OAuth authentication with Google
- **GenServer**: Background polling for bot status updates

### Integrations
- **Google Calendar API**: Event synchronization
- **Recall.ai API**: Meeting bot management and transcription
- **OpenAI API**: AI content generation
- **LinkedIn API**: Social media posting (simulated)

### Key Modules
- `SMG.Integrations.GoogleCalendar`: Calendar sync and event management
- `SMG.Integrations.RecallAI`: Bot creation and management
- `SMG.Services.RecallPoller`: Background polling for bot status
- `SMG.AI.ContentGenerator`: AI-powered content creation
- `SMG.Services.SocialMediaPoster`: Social media publishing

## Development Notes

### Shared Recall.ai Account
Since this uses a shared Recall.ai account:
- The system uses polling instead of webhooks for bot status updates
- Each bot is tracked by its unique ID to avoid conflicts
- The polling service runs every 30 seconds to check for updates

### Database Schema
- `users`: User accounts linked to Google OAuth
- `google_accounts`: Multiple Google accounts per user
- `calendar_events`: Synced calendar events with meeting metadata
- `social_posts`: Generated social media content with status tracking

### Security Considerations
- OAuth tokens are securely stored and refreshed automatically
- API keys are loaded from environment variables
- User data isolation ensures privacy between accounts
- All sensitive information is properly encrypted

## Troubleshooting

### Common Issues

1. **Google Calendar not syncing**:
   - Check that the Google Calendar API is enabled
   - Verify OAuth scopes include calendar access
   - Ensure the access token is valid

2. **Recall.ai bot not joining**:
   - Verify the API token is correct
   - Check that the meeting link is valid
   - Ensure the meeting is scheduled in the future

3. **AI content generation failing**:
   - Check OpenAI API key and credits
   - Verify the transcript URL is accessible
   - Review the OpenAI API rate limits

### Logs and Debugging
- Check logs for API responses and errors
- Use `mix phx.server` with debug logging enabled
- Monitor the Recall poller GenServer for bot status updates

## Next Steps

Potential enhancements:
- Real-time transcript streaming during meetings
- More social media platforms (Twitter, Facebook, Instagram)
- Custom content templates and branding
- Analytics and engagement tracking
- Team collaboration features
- Advanced AI prompt customization

## Support

For issues or questions:
1. Check the application logs for error details
2. Verify all API keys and credentials are correct
3. Ensure all external services (Google, Recall.ai, OpenAI) are operational
4. Review the troubleshooting section above

---

**Note**: This application is designed for demonstration purposes. In a production environment, additional security measures, error handling, and monitoring should be implemented.
