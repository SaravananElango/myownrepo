import requests
import json
import os
from dotenv import load_dotenv

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(dotenv_path=os.path.join(SCRIPT_DIR, ".env"))  # Load environment variables from the script directory

API_KEY = os.getenv("API_KEY")
CHANNEL_HANDLE = "MrBeast"

if not API_KEY:
    raise RuntimeError(
        "API_KEY is not set. Create a .env file next to video_stats.py with API_KEY=your_key, or export API_KEY in your shell."
    )

if not CHANNEL_HANDLE:
    raise RuntimeError("CHANNEL_HANDLE is not set.")


def get_playlist_id():
    try:

        url = f"https://youtube.googleapis.com/youtube/v3/channels?part=contentDetails&forHandle={CHANNEL_HANDLE}&key={API_KEY}" 
        response = requests.get(url)
        response.raise_for_status()  # Check if the request was successful
        data = response.json()
        #print (json.dumps(data, indent=4))
        channel_items = data["items"][0]
        channel_playlist_id = channel_items["contentDetails"]["relatedPlaylists"]["uploads"]
        return channel_playlist_id

    except requests.exceptions.RequestException as e:
        raise RuntimeError(f"YouTube API request failed: {e}") from e


if __name__ == "__main__":
    print(get_playlist_id())