import requests
import json
import os
from dotenv import load_dotenv
from datetime import date, datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(dotenv_path=os.path.join(SCRIPT_DIR, ".env"))  # Load environment variables from the script directory

API_KEY = os.getenv("API_KEY")
CHANNEL_HANDLE = "MrBeast"
maxResults = 50


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

def get_video_ids(playlistID):
    video_ids = []
    page_token = None

    base_url = f"https://youtube.googleapis.com/youtube/v3/playlistItems?part=contentDetails&maxResults={maxResults}&playlistId={playlistID}&key={API_KEY}"
   
    try:
        while True:
            url = base_url
            if page_token:
                url += f"&pageToken={page_token}"
            response = requests.get(url)
            response.raise_for_status()  # Check if the request was successful
            data = response.json()
            #print (json.dumps(data, indent=4))
            for item in data["items"]:
                video_id = item.get("contentDetails", {}).get("videoId")
                if not video_id:
                    video_id = item.get("snippet", {}).get("resourceId", {}).get("videoId")
                if video_id:
                    video_ids.append(video_id)
            page_token = data.get("nextPageToken")
            if not page_token:
                break

        return video_ids


    except requests.exceptions.RequestException as e:
        raise e



def extract_video_data (video_ids):
    extracted_data = []


    def batch_list (video_id_list , batch_size):
        for video_id in range (0,len(video_id_list), batch_size):
            yield video_id_list[video_id:video_id + batch_size]

    try:
        for batch in batch_list(video_ids,maxResults):
            video_ids_str = ",".join(batch)
            # Process each batch of video IDs
            url = f"https://youtube.googleapis.com/youtube/v3/videos?part=contentDetails&part=snippet&part=statistics&id={video_ids_str}&key={API_KEY}"

            response = requests.get(url)
            response.raise_for_status()  # Check if the request was successful
            data = response.json()

            for item in data.get('items', []):
                video_data = {
                    'video_id': item.get('id'),
                    'title': item.get('snippet', {}).get('title'),
                    'published_at': item.get('snippet', {}).get('publishedAt'),
                    'view_count': item.get('statistics', {}).get('viewCount',None),
                    'like_count': item.get('statistics', {}).get('likeCount',None),
                    'comment_count': item.get('statistics', {}).get('commentCount',None)
                }
                extracted_data.append(video_data)

        return extracted_data

    except requests.exceptions.RequestException as e:
        raise e
    

def save_to_json(extracted_data):
    file_path = f"./etl-python/video_data_{date.today()}.json"

    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(extracted_data, f,indent=4,ensure_ascii=False)

if __name__ == "__main__":
    playlist_id = get_playlist_id()
    video_ids = get_video_ids(playlist_id)
    video_data = extract_video_data(video_ids)
    save_to_json(video_data)