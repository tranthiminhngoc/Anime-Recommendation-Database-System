import requests 
from bs4 import BeautifulSoup
from sqlalchemy import create_engine, Table, Column, Integer, Float, String, MetaData, insert
import urllib
import time
import re

header = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 coc_coc_browser/132.0.0'}

# Tạo kết nối tới SQL Server
params = urllib.parse.quote_plus(
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=...;"  # Tên server
    "DATABASE=Anime;"  # Tên cơ sở dữ liệu
    "UID=sa;"  # Username để đăng nhập SQL Server
    "PWD=...;"  # Mật khẩu
)

# Tạo engine kết nối tới SQL Server
engine = create_engine("mssql+pyodbc:///?odbc_connect=%s" % params)
connection = engine.connect()

# Khởi tạo metadata và định nghĩa bảng
metadata = MetaData(bind=engine)

# Định nghĩa bảng AnimeData6
anime_table = Table('AnimeData5', metadata, autoload=True)

# URL trang web cần scrape
base_url = 'https://myanimelist.net/topanime.php'

# Hàm retry để gửi request với số lần thử lại
def fetch_url(url, max_retries=3, sleep_time=5):
    for attempt in range(max_retries):
        try:
            response = requests.get(url, headers=header)
            if response.status_code == 200:
                return response
        except requests.exceptions.RequestException as e:
            print(f"Lỗi khi truy cập {url}: {e}. Thử lại lần {attempt + 1}/{max_retries}")
            time.sleep(sleep_time)
    return None

# Hàm để lấy thông tin từ trang anime
def scrape_anime_list(html_soup):
    for anime in html_soup.select('tr.ranking-list'):
        anime_name = anime.find(class_='fl-l fs14 fw-b anime_ranking_h3').get_text(strip=True)
        print(f"Anime name being scraped: {anime_name}")

        anime_score = anime.select_one('.score-label').text.strip()
        anime_rank = anime.select_one('.top-anime-rank-text').text.strip()

        # Scrape thể loại của anime từ trang chi tiết
        anime_url = anime.select_one('.title .hoverinfo_trigger').get('href')
        anime_detail = fetch_url(anime_url)

        if anime_detail is not None:
            detail_soup = BeautifulSoup(anime_detail.text, 'html.parser')
            genres = ', '.join([genre.text for genre in detail_soup.select('span[itemprop="genre"]')])

            # Scraping additional information
            def get_clean_text(selector, soup):
                element = soup.select_one(selector)
                return re.sub(r'[^\d]', '', element.get_text(strip=True)) if element else "N/A"
            
            # Function to get text by label
            def get_text_by_label(label, soup):
                label_element = soup.find_all('div', class_='spaceit_pad')
                for element in label_element:
                    if label in element.get_text():
                        # Get text after label
                        return element.get_text().split(label)[-1].strip()
                return "N/A"

            animetype = get_text_by_label("Type:", detail_soup)
            studio = get_text_by_label("Studios:", detail_soup)
            premiered = get_text_by_label("Premiered:", detail_soup)
            synopsis = detail_soup.select_one('p[itemprop="description"]').text.strip() if detail_soup.select_one('p[itemprop="description"]') else "N/A"
            episodes = get_clean_text('div.spaceit_pad:-soup-contains("Episodes:")', detail_soup)
            duration = get_text_by_label("Duration:", detail_soup)
            status = get_text_by_label("Status:", detail_soup)
            rating = get_text_by_label("Rating:", detail_soup)
            popularity = get_clean_text('div.spaceit_pad:-soup-contains("Popularity:")', detail_soup)
            members = get_clean_text('div.spaceit_pad:-soup-contains("Members:")', detail_soup)
            favorites = get_clean_text('div.spaceit_pad:-soup-contains("Favorites:")', detail_soup)

            # Chuẩn bị dữ liệu để chèn vào cơ sở dữ liệu
            data = {
                'AnimeName': anime_name,
                'Score': float(anime_score) if anime_score.replace('.', '', 1).isdigit() else None,
                'Ranking': int(anime_rank) if anime_rank.isdigit() else None,
                'Genres': genres,
                'AnimeType': animetype,
                'Studio': studio,
                'Premiered': premiered,
                'Synopsis': synopsis,
                'Episodes': int(episodes) if episodes.isdigit() else None,
                'AnimeStatus': status,
                'Duration': duration,
                'Popularity': popularity,
                'Rating': rating,
                'Members': int(members) if members.isdigit() else None,
                'Favorites': int(favorites) if favorites.isdigit() else None
            }

            # Chèn dữ liệu vào cơ sở dữ liệu
            with engine.connect() as connection:
                insert_stmt = insert(anime_table).values(data)
                connection.execute(insert_stmt)
        else:
            print(f"Không thể tải trang: {anime_url}")

# Bắt đầu quá trình scrape 3 trang đầu tiên
for page in range(80,120):  # Crawl 3 pages
    url = base_url if page == 0 else f'{base_url}?limit={page*50}'
    print('Now scraping page:', url)
    
    # Thực hiện request với cơ chế retry
    r = fetch_url(url)
    if r is not None:
        html_soup = BeautifulSoup(r.text, 'html.parser')

        # Scrape thông tin anime từ trang hiện tại
        scrape_anime_list(html_soup)
    
    # Tạm dừng giữa các lần request để tránh bị chặn
    time.sleep(15)

print("Đã lưu dữ liệu anime vào SQL Server.")
