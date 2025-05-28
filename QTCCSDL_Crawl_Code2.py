from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.common.exceptions import NoSuchElementException
from time import sleep
import pyodbc

def connect_to_sql():
    conn = pyodbc.connect(
        'DRIVER={ODBC Driver 17 for SQL Server};'
        'SERVER=DESKTOP-J3SL5AF;'
        'DATABASE=Anime_list;'
        'UID=sa;'
        'PWD=....'
    )
    return conn

def insert_data(conn, AnimeName, AnimeType, Studio, Premiered, Score, 
                Ranking, Genres, Synopsis, Episodes, AnimeStatus, Duration, 
                Popularity, Rating, Members, Favorites):
    cursor = conn.cursor()

    # chuyển đổi giá trị thành số nguyên, nếu không hợp lệ sẽ trả về None
    def convert_to_int(value):
        if value is None or value == 'Unknown' or not value.replace(',', '').isdigit():
            return None
        return int(value.replace(',', '')) 

    Episodes = convert_to_int(Episodes)
    Ranking = convert_to_int(Ranking)
    Popularity = convert_to_int(Popularity)
    Favorites = convert_to_int(Favorites)
    Members = convert_to_int(Members)

    # Kiểm tra xem anime đã tồn tại trong cơ sở dữ liệu hay chưa
    cursor.execute("SELECT COUNT(*) FROM AnimeDataset1 WHERE AnimeName=?", (AnimeName,))
    count = cursor.fetchone()[0]
    if count == 0:
        cursor.execute(
            "INSERT INTO AnimeDataset1 (AnimeName, AnimeType, Studio, Premiered, Score, \
                                        Ranking, Genres, Synopsis, Episodes, AnimeStatus, \
                                        Duration, Popularity, Rating, Members, Favorites) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                                       (AnimeName, AnimeType, Studio, Premiered, Score, 
                                        Ranking, Genres, Synopsis, Episodes, AnimeStatus, 
                                        Duration, Popularity, Rating, Members, Favorites)
        )
        conn.commit()
        print(f"Đã thêm anime: {AnimeName}")
    else:
        print(f"Anime '{AnimeName}' đã tồn tại.")

def crawl_data(conn, list_link):
    for link in list_link:
        driver.get(link)
        sleep(5)  

        try:
            AnimeName = driver.find_element(
                By.CSS_SELECTOR, 'h1.title-name'
                ).text
        except NoSuchElementException:
            AnimeName = None

        try:
            Score = driver.find_element(
                By.CSS_SELECTOR, 'div.score-label'
                ).text
        except NoSuchElementException:
            Score = None

        try:
            Synopsis = driver.find_element(
                By.XPATH, './/p[@itemprop="description"]'
                ).text
        except NoSuchElementException:
            Synopsis = None

        # Khởi tạo giá trị mặc định
        AnimeType = Studio = Premiered = Episodes = AnimeStatus = Duration = None
        Rating = Favorites = Ranking = Members = Genres = Popularity = None

        div_elements = driver.find_elements(By.CSS_SELECTOR, 'div.spaceit_pad')


        for div in div_elements:
            div_text = div.text.split(':')
            if len(div_text) < 2:
                continue

            key, value = div_text[0].strip(), div_text[1].strip()

            if key == 'Type':
                AnimeType = value
            elif key == 'Studios':
                Studio = value
            elif key == 'Premiered':
                Premiered = value
            elif key == 'Episodes':
                Episodes = value
            elif key == 'Status':
                AnimeStatus = value
            elif key == 'Duration':
                Duration = value
            elif key == 'Rating':
                Rating = value
            elif key == 'Favorites':
                Favorites = value
            elif key == 'Ranked':
                Ranking = value[1:]  
            elif key == 'Members':
                Members = value
            elif any(word in key for word in ['Genre', 'Genres', 
                                              'Demographic', 'Theme']):
                if Genres:
                    Genres += ', ' + value  
                else:
                    Genres = value 
            elif key == 'Popularity':
                Popularity = value[1:]  

        insert_data(conn, AnimeName, AnimeType, Studio, Premiered, Score, 
                    Ranking, Genres, Synopsis, Episodes, AnimeStatus, 
                    Duration, Popularity, Rating, Members, Favorites)

def get_anime_links(start_page, end_page, step=50):
    list_link = []
    for page in range(start_page, end_page, step):
        url = f'https://myanimelist.net/topanime.php?limit={page}'
        driver.get(url)
        sleep(5)

        try:
            list_tr = driver.find_elements(
                By.CSS_SELECTOR, 'tr.ranking-list')
            for item in list_tr:
                link = item.find_element(
                    By.CSS_SELECTOR, 'a.hoverinfo_trigger'
                    ).get_attribute('href')
                list_link.append(link)
        except NoSuchElementException:
            print('Không tìm được danh sách anime')
            continue

    return list_link

# Main script
if __name__ == "__main__":
    driver = webdriver.Chrome()

    # Lấy danh sách các liên kết anime từ trang topanime
    list_link = get_anime_links(8900,8950)

    print(f"Đã thu thập được {len(list_link)} liên kết anime.")

    # Kết nối cơ sở dữ liệu và thu thập dữ liệu chi tiết từ từng liên kết
    conn = connect_to_sql()
    crawl_data(conn, list_link)
    conn.close()

    driver.quit()
