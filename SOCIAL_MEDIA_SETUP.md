# Social Media Integration Setup

This guide explains how to set up Facebook and LinkedIn integrations for posting social media content.

## Facebook/Meta Platform Setup

### 1. Create Facebook App

1. Go to [Facebook Developers](https://developers.facebook.com/)
2. Click "Create App" → "Business" → "Next"
3. Fill in app details:
   - App name: "SM Content Generator"
   - App contact email: your email
   - Business account: select or create

### 2. Add Required Products

From your app dashboard, add these products:

#### **Manage everything on your Page**
- Required for posting to Facebook Pages
- Provides permissions: `pages_manage_posts`, `pages_read_engagement`, `pages_show_list`

### 3. Get App Credentials

1. Go to Settings → Basic
2. Copy your **App ID** and **App Secret**

### 4. Get Page Access Token

1. Go to Tools → Graph API Explorer
2. Select your app
3. Add permissions: `pages_manage_posts`, `pages_show_list`
4. Generate access token
5. Convert to long-lived token using:
   ```
   GET /oauth/access_token?grant_type=fb_exchange_token&client_id={app-id}&client_secret={app-secret}&fb_exchange_token={short-lived-token}
   ```

### 5. Get Page ID

1. Go to your Facebook page
2. Click "About" → "Page transparency" → "Page ID"
3. Or use Graph API: `GET /me/accounts` with your access token

### 6. Environment Variables (Optional - for development/testing)

Add to your `.env` file for development/testing:
```bash
FACEBOOK_APP_ID=your_app_id_here
FACEBOOK_APP_SECRET=your_app_secret_here
FACEBOOK_ACCESS_TOKEN=your_personal_access_token  # Optional: for testing without OAuth
```

**Note:** In production, users should connect their Facebook accounts through OAuth. Environment variables are only for development/testing.

## LinkedIn Setup

### 1. Create LinkedIn App

1. Go to [LinkedIn Developers](https://www.linkedin.com/developers/)
2. Click "Create app"
3. Fill in app details:
   - App name: "SM Content Generator"
   - LinkedIn Page: Your company page
   - App description: "Social media content generator"
   - App logo: Upload a logo
   - Legal agreement: Check and agree

### 2. Request Products

Request access to these products:

#### **Share on LinkedIn**
- Allows posting on behalf of members
- Provides scope: `w_member_social`

#### **Sign In with LinkedIn using OpenID Connect**
- For user authentication
- Provides scope: `openid`, `profile`, `email`

### 3. Get App Credentials

1. Go to your app → "Auth" tab
2. Copy **Client ID** and **Client Secret**

### 4. Set Redirect URLs

1. In the "Auth" tab, add redirect URLs:
   - `http://localhost:4000/auth/linkedin/callback` (development)
   - `https://yourdomain.com/auth/linkedin/callback` (production)

### 5. Get Access Token

For development, you can use the LinkedIn OAuth flow:

1. Redirect user to:
   ```
   https://www.linkedin.com/oauth/v2/authorization?response_type=code&client_id={client_id}&redirect_uri={redirect_uri}&scope=openid%20profile%20w_member_social
   ```

2. Exchange code for token:
   ```
   POST https://www.linkedin.com/oauth/v2/accessToken
   Content-Type: application/x-www-form-urlencoded

   grant_type=authorization_code&code={authorization_code}&client_id={client_id}&client_secret={client_secret}&redirect_uri={redirect_uri}
   ```

### 6. Environment Variables

Add to your `.env` file:
```bash
LINKEDIN_CLIENT_ID=your_client_id_here
LINKEDIN_CLIENT_SECRET=your_client_secret_here
LINKEDIN_ACCESS_TOKEN=your_access_token_here
```

## Testing the Integration

### 1. Update Environment

Copy the environment variables from `.env.example` to `.env` and fill in your credentials.

### 2. Test Facebook Posting

```elixir
# In IEx console
social_post = %SMG.Social.SocialPost{
  content: "Test post from my app!",
  platform: "facebook",
  user_id: 1
}

SMG.Integrations.Facebook.post_content(nil, social_post)
```

### 3. Test LinkedIn Posting

```elixir
# In IEx console
social_post = %SMG.Social.SocialPost{
  content: "Test LinkedIn post from my app! #socialmedia #automation",
  platform: "linkedin",
  user_id: 1
}

SMG.Integrations.LinkedIn.post_content(nil, social_post)
```

## Important Notes

### Facebook
- Page access tokens are required for posting to pages
- User access tokens only allow posting to personal timeline
- Tokens expire - implement refresh logic for production
- Review process required for apps requesting advanced permissions

### LinkedIn
- Access tokens expire after 60 days by default
- Requires company page for some features
- Review process required for Marketing Developer Platform access
- Rate limits: 500 requests per day for Share on LinkedIn

### Security
- Never commit access tokens to git
- Use environment variables for all credentials
- Implement token refresh logic for production
- Monitor API usage and errors

## Troubleshooting

### Common Facebook Errors
- `(#200) Requires either publish_to_groups permission...` - Need Page access token
- `Invalid OAuth access token` - Token expired or incorrect
- `(#100) Unsupported post request` - Check API endpoint and parameters

### Common LinkedIn Errors
- `Invalid access token` - Token expired or incorrect scope
- `Forbidden` - Missing required permissions
- `Member does not have permission to create content` - Need w_member_social scope

### Getting Help
- Facebook: [Graph API Documentation](https://developers.facebook.com/docs/graph-api/)
- LinkedIn: [API Documentation](https://docs.microsoft.com/en-us/linkedin/)
- Both platforms have developer communities and support