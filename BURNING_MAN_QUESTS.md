# 🔥 Burning Man Quest System

Quick and dirty quest system for each persona at Burning Man! Each persona has a two-part goal:

## 🎭 Persona Quests

### Buddy 
- **Get To Goal**: Find five people and genuinely help them with something meaningful
- **Do Goal**: Get a 10/10 satisfaction score from all five people, then retire and become Bad Buddy - no more helping anyone!
- **Progress**: 0/5

### Jax 
- **Get To Goal**: Convince a bar or camp to let you be their jukebox/DJ
- **Do Goal**: Become the jukebox - play music and be the life of the party
- **Progress**: 0/1

### Neon
- **Get To Goal**: Find an art car playing good house music
- **Do Goal**: Get on the art car and dance/DJ - become one with the beat
- **Progress**: 0/1

### Sparkle
- **Get To Goal**: Find someone having a terrible time at Burning Man
- **Do Goal**: Cheer them up and make their day magical with sparkles and joy
- **Progress**: 0/1

### Zorp
- **Get To Goal**: Find the most exclusive, weird event or art installation
- **Do Goal**: Infiltrate it and document the strange human behaviors for alien analysis
- **Progress**: 0/1

### Mobius (Gibson)
- **Get To Goal**: Get on the radio (BMIR or pirate station)
- **Do Goal**: Wax philosophical and play IDM/ambient music to blow minds
- **Progress**: 0/1

### Crash
- **Get To Goal**: Find the most chaotic, high-energy event or rave
- **Do Goal**: Become the hype person - get everyone amped up and create controlled chaos
- **Progress**: 0/1

### The Cube
- **Get To Goal**: Find the Temple or most sacred/meaningful space
- **Do Goal**: Become a guardian/oracle - help people find what they're looking for
- **Progress**: 0/1

## 🚀 Quick Setup

1. **Enable Quest Mode in Home Assistant:**
   ```yaml
   # Add to configuration.yaml:
   input_boolean:
     burning_man_quest_mode:
       name: "🔥 Burning Man Quest Mode"
       icon: mdi:fire
   ```

2. **Turn on the quest mode toggle in HASS dashboard**

3. **The goal service will automatically bypass normal goals and use persona quests**

## 🎯 How It Works

- When `burning_man_quest_mode` is ON, the goal service bypasses normal goal selection
- Each persona gets their quest loaded from `config/persona_themes.yml`
- Quest progress is tracked in the YAML file
- Update progress via HASS frontend or API calls

## 🔧 API Endpoints

- `POST /api/v1/burning_man/quest/progress` - Increment quest progress
- `GET /api/v1/burning_man/quest/status` - Get current quest status

## 📱 HASS Frontend

Add the dashboard card from `config/hass_burning_man_quest.yaml` to track and update quest progress.

## 🎪 Special Features

- **Buddy Retirement**: When Buddy completes all 5 helps, he "retires" and becomes Bad Buddy
- **Longer Quest Times**: Quests last 6 hours instead of normal 2-hour goals
- **Progress Persistence**: Quest progress is saved to the YAML file and survives restarts

Enjoy the playa! 🏕️✨