--Xem có bao nhiêu Trigger
SELECT name AS TriggerName
FROM sys.triggers
WHERE parent_id = OBJECT_ID('dbo.AnimeData');
DROP TRIGGER IF EXISTS Convert_Duration_Trigger;
-- Xem có bao nhiêu Procedure
SELECT name
FROM sys.objects
WHERE type = 'P';

DROP Procedure RemoveDuplicateRows;
--1. Xóa dòng trống 
CREATE PROCEDURE XoaDongTrong
AS
BEGIN
    -- Xóa các dòng có AnimeID nhưng tất cả các cột còn lại đều trống hoặc NULL
    DELETE FROM AnimeData
    WHERE 
        -- Cột AnimeName trống hoặc NULL
        (AnimeName IS NULL OR LTRIM(RTRIM(AnimeName)) = '');
END;
--Gọi thủ tục
EXEC XoaDongTrong;


--2.Xóa các khoảng trắng 
CREATE PROCEDURE XoaKhoangTrang
    @TableName NVARCHAR(255),  -- Tên bảng
    @ColuAnimeDataName NVARCHAR(255)  -- Tên cột cần loại bỏ khoảng trắng
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX);
    -- Câu lệnh SQL động để cập nhật tất cả các bản ghi trong cột đã chỉ định và loại bỏ khoảng trắng ở đầu và cuối
    SET @SQL = N'UPDATE ' + @TableName + 
               ' SET ' + @ColuAnimeDataName + ' = LTRIM(RTRIM(' + @ColuAnimeDataName + '))';
    -- Thực thi câu lệnh SQL động
    EXEC sp_executesql @SQL;
END;
--Gọi thủ tục
EXEC XoaKhoangTrang
    @TableName = 'AnimeData',
    @ColuAnimeDataName = 'Studio';

--3. Chuyển đổi kiểu:
 --Chuyển Premiered từ Null, ? thành N/A
CREATE TRIGGER Clean_Trigger
ON [dbo].[AnimeData]
AFTER INSERT, UPDATE
AS
BEGIN
    UPDATE [dbo].[AnimeData]
    SET Premiered = 'N/A'
   -- Chỉ cập nhật bản ghi có thay đổi
    WHERE Premiered IS NULL OR Premiered = '?'
	AND AnimeID IN (SELECT AnimeID FROM INSERTED)
    UPDATE [dbo].[AnimeData]
    SET Studio = 'N/A'
    WHERE Studio IS NULL OR Studio = 'None found, add some'
	AND AnimeID IN (SELECT AnimeID FROM INSERTED)
 --Blanks của Epsido => chuyển về 1 tập.
    UPDATE [dbo].[AnimeData]
    SET Episodes = 1
    WHERE Episodes IS NULL
	AND AnimeID IN (SELECT AnimeID FROM INSERTED)
END;


UPDATE [dbo].[AnimeData]
SET Premiered = Premiered;
UPDATE [dbo].[AnimeData]
SET Studio = Studio;
UPDATE [dbo].[AnimeData]
SET Episodes = Episodes;


--6. Đổi Duration thành phút
-- Thêm cột mới: Duration_min
ALTER TABLE [dbo].[AnimeData]
ADD Duration_min Float;
-- Tạo trigger chuyển duration thành phút
CREATE TRIGGER Convert_Duration_Trigger
ON [dbo].[AnimeData]
AFTER INSERT, UPDATE
AS
BEGIN
    -- Kiểm tra mức độ lồng nhau của trigger
    IF TRIGGER_NESTLEVEL() > 1
        RETURN;  -- Dừng trigger nếu nó đã bị gọi trong quá trình lồng nhau

    -- Chuyển các giá trị khác 'unknown' thành phút
    UPDATE [dbo].[AnimeData]
    SET Duration_min = 
        CASE 
            -- Trường hợp có định dạng giờ và phút
            WHEN Duration LIKE '%hr. %min.%' THEN 
                CAST(SUBSTRING(Duration, 1, CHARINDEX('hr.', Duration) - 1) AS INT) * 60 + 
                CAST(SUBSTRING(Duration, CHARINDEX('hr.', Duration) + 4, CHARINDEX('min.', Duration) - CHARINDEX('hr.', Duration) - 4) AS INT)

            -- Trường hợp có định dạng phút cho mỗi tập
            WHEN Duration LIKE '%min. per ep.%' THEN 
                CAST(SUBSTRING(Duration, 1, CHARINDEX(' min.', Duration) - 1) AS INT)

            -- Trường hợp có định dạng phút
            WHEN Duration LIKE '%min%' THEN 
                CAST(SUBSTRING(Duration, 1, CHARINDEX(' min', Duration) - 1) AS INT)

            -- Trường hợp có định dạng giờ
            WHEN Duration LIKE '%hr%' THEN 
                CAST(SUBSTRING(Duration, 1, CHARINDEX(' hr', Duration) - 1) AS INT) * 60

            -- Trường hợp có định dạng giây
            WHEN Duration LIKE '%sec%' THEN 
                ROUND(CAST(SUBSTRING(Duration, 1, CHARINDEX(' sec', Duration) - 1) AS FLOAT) / 60.0, 2)

            -- Trường hợp là 'unknown', giữ nguyên giá trị
            WHEN Duration = 'unknown' THEN NULL  -- Giữ nguyên giá trị 'unknown'
        END
    WHERE Duration IS NOT NULL
    AND AnimeID IN (SELECT AnimeID FROM INSERTED);  -- Chỉ cập nhật các hàng có trong bảng INSERTED

    -- Với những Duration = 'unknown', thì Duration_min bằng TBC của các bộ anime có cùng episodes
    UPDATE [dbo].[AnimeData]
    SET Duration_min = ROUND(
        (
            SELECT AVG(Duration_min)
            FROM [dbo].[AnimeData] AS sub
            WHERE sub.Episodes = [dbo].[AnimeData].Episodes
            AND sub.Duration_min IS NOT NULL  -- Chỉ tính trung bình cho những bản ghi không NULL
        ), 2)  -- Làm tròn đến 2 chữ số phần thập phân
    WHERE Duration_min IS NULL
   AND AnimeID IN (SELECT AnimeID FROM INSERTED);  -- Chỉ cập nhật các hàng có trong bảng INSERTED
END;
UPDATE [dbo].[AnimeData]
SET Duration = Duration;

--7.Trigger để kiểm tra tính hợp lệ của dữ liệu:
CREATE TRIGGER CheckAnimeData
ON AnimeData
AFTER INSERT, UPDATE
AS
BEGIN
    -- Kiểm tra Score phải nằm trong khoảng từ 0 đến 10
    IF EXISTS (SELECT 1 FROM inserted WHERE Score < 0 OR Score > 10)
    BEGIN
        RAISERROR('Score must be between 0 and 10', 16, 1)
        ROLLBACK TRANSACTION
        RETURN
    END

    -- Kiểm tra Ranking phải là số dương
    IF EXISTS (SELECT 1 FROM inserted WHERE Ranking <= 0)
    BEGIN
        RAISERROR('Ranking must be a positive number', 16, 1)
        ROLLBACK TRANSACTION
        RETURN
    END

    -- Kiểm tra Members và Favorites không được âm
    IF EXISTS (SELECT 1 FROM inserted WHERE Members < 0 OR Favorites < 0)
    BEGIN
        RAISERROR('Members and Favorites must be non-negative', 16, 1)
        ROLLBACK TRANSACTION
        RETURN
    END
END

--Câu 8  Viết thủ tục để xóa các chú thích ở cột rating
CREATE PROCEDURE RemoveRatingComments
AS
BEGIN
    -- Cập nhật cột Rating, giữ lại các giá trị chính và xóa phần chú thích
    UPDATE AnimeData
    SET Rating = CASE
        WHEN Rating LIKE 'G%' THEN 'G'
        WHEN Rating LIKE 'PG-13%' THEN 'PG-13'
        WHEN Rating LIKE 'R+%' THEN 'R+'
        WHEN Rating LIKE 'PG%' THEN 'PG'
        WHEN Rating LIKE 'None%' THEN 'None'
		Else 'R-17+'
    END
    WHERE Rating LIKE '%-%'
END
--Gọi thủ tục
exec  RemoveRatingComments;

--9. kiểm tra dòng trùng lặp
CREATE PROCEDURE RemoveDuplicateRows
AS
BEGIN
    -- Xóa các dòng trùng lặp dựa trên AnimeID, giữ lại bản ghi đầu tiên
    WITH DuplicateRows AS (
        SELECT 
            AnimeID, 
            ROW_NUMBER() OVER(PARTITION BY AnimeID ORDER BY (SELECT NULL)) AS RowNum
        FROM 
            dbo.AnimeData 
    )
    DELETE FROM DuplicateRows
    WHERE RowNum > 1;  -- Chỉ xóa các bản ghi có RowNum lớn hơn 1 (tức là bản ghi trùng lặp)
END;
EXEC RemoveDuplicateRows;
-------------------------------------------Tách bảng--------------------------
-select * from [dbo].[AnimeData] 

--Tạo Anime
SELECT 
    AnimeID,       
    AnimeName, 
    Duration_min, 
    Synopsis, 
    Episodes, 
    AnimeStatus
INTO Anime
FROM AnimeData;
ALTER TABLE Anime
ADD CONSTRAINT PK_Anime PRIMARY KEY (AnimeID);

-- Tạo bảng Statistic
-- Tạo bảng Statistic từ bảng AnimeData
SELECT 
    IDENTITY(INT, 1, 1) AS StatisticID, 
    Ranking,
    Favorites,
    Score,
    Popularity,
    Members
INTO Statistic
FROM [dbo].[AnimeData];
-- Thiết lập StatisticID là khóa chính
ALTER TABLE Statistic
ADD CONSTRAINT PK_Statistic PRIMARY KEY (StatisticID);
-- Thêm cột StatisticID vào bảng Anime
ALTER TABLE [dbo].[Anime]
ADD StatisticID INT;
-- Câph nhật cột StatisticID trong bảng Anime
UPDATE [dbo].[Anime]
SET StatisticID = s.StatisticID
FROM [dbo].[AnimeData] a
JOIN Statistic s ON a.Ranking = s.Ranking 
                 AND a.Favorites = s.Favorites
                 AND a.Score = s.Score
                 AND a.Popularity = s.Popularity
                 AND a.Members = s.Members;
-- Thêm rảng buộc khoá ngoại cho cột StatisticID
ALTER TABLE [dbo].[Anime]
ADD CONSTRAINT FK_Anime_Statistic 
FOREIGN KEY (StatisticID) REFERENCES Statistic(StatisticID);

-- Tạo bảng Premiered
-- Tạo bảng Premiered và chèn dữ liệu từ bảng AnimeData
SELECT DISTINCT Premiered
INTO Premiered
FROM AnimeData
WHERE Premiered IS NOT NULL;
-- Thêm cột PremieredID tự động tăng làm khóa chính cho bảng Premiered
ALTER TABLE Premiered
ADD PremieredID INT IDENTITY(1,1) PRIMARY KEY;
-- Thêm cột PremieredID vào bảng Anime (chứa liên kết khóa ngoại đến bảng Premiered)
ALTER TABLE Anime
ADD PremieredID INT;
-- Cập nhật cột PremieredID trong bảng Anime từ bảng Premiered
UPDATE Anime
SET Anime.PremieredID = p.PremieredID
FROM AnimeData AS a
JOIN Premiered AS p ON a.Premiered = p.Premiered;
-- Thêm ràng buộc khóa ngoại để liên kết cột PremieredID của bảng Anime với bảng Premiered
ALTER TABLE [dbo].[Anime]
ADD CONSTRAINT FK_Anime_Premiered
FOREIGN KEY (PremieredID) REFERENCES [dbo].[Premiered](PremieredID);

-- Tạo bảng Rating
-- Tạo bảng Rating và chèn các giá trị Rating duy nhất từ AnimeData
SELECT DISTINCT Rating
INTO Rating
FROM AnimeData
WHERE Rating IS NOT NULL;
-- Thêm cột RatingID với giá trị tự tăng vào bảng vừa tạo
ALTER TABLE Rating
ADD RatingID INT IDENTITY(1,1) PRIMARY KEY;
-- Thêm cột RatingID vào bảng Anime
ALTER TABLE Anime
ADD RatingID INT;
-- Cập nhật giá trị của RatingID trong bảng Anime
UPDATE Anime
SET Anime.RatingID = r.RatingID
FROM AnimeData AS a
JOIN Rating AS r ON a.Rating = r.Rating;
-- Thêm khóa ngoại vào cột RatingID trong bảng Anime để tham chiếu đến RatingID trong bảng Rating
ALTER TABLE [dbo].[Anime]
ADD CONSTRAINT FK_Anime_Rating
FOREIGN KEY (RatingID) REFERENCES [dbo].[Rating](RatingID);

-- Tạo bảng AnimeType
-- Tạo bảng AnimeType và chèn các giá trị AnimeType duy nhất từ bang AnimeData
SELECT DISTINCT AnimeType
INTO AnimeType
FROM AnimeData
WHERE AnimeType IS NOT NULL;
-- Thêm cột AnimeTypeID với giá trị tự tăng vào bảng vừa tạo
ALTER TABLE AnimeType
ADD AnimeTypeID INT IDENTITY(1,1) PRIMARY KEY;
-- Thêm cột AnimeTypeID vào bảng Anime
ALTER TABLE Anime
ADD AnimeTypeID INT;
-- Cập nhật AnimeTypeID trong bảng AnimeData6 dựa trên giá trị AnimeType
UPDATE Anime
SET Anime.AnimeTypeID = b.AnimeTypeID
FROM AnimeData AS a
JOIN AnimeType AS b ON a.AnimeType = b.AnimeType;
-- Thêm ràng buộc khoá chính, khoá ngoại của Anime và AnimeType 
ALTER TABLE [dbo].[Anime]
ADD CONSTRAINT FK_Anime_AnimeType
FOREIGN KEY (AnimeTypeID) REFERENCES [dbo].[AnimeType](AnimeTypeID);

-- Tạo bảng Genres
CREATE TABLE Genres (
    GenresID INT IDENTITY(1,1) PRIMARY KEY,
    GenreName NVARCHAR(500) UNIQUE
);
-- Tách và chèn dữ liệu vào bảng Genres
;WITH GenreList AS (
    SELECT DISTINCT
        TRIM(value) AS GenreName
    FROM AnimeData
    CROSS APPLY STRING_SPLIT(Genres, ',')  
)
INSERT INTO Genres (GenreName)
SELECT GenreName FROM GenreList;
-- Tạo bảng Anime_genres
CREATE TABLE Anime_genres (
    AnimegenresID INT IDENTITY(1,1) PRIMARY KEY,
    AnimeID INT,
    GenresID INT,
    FOREIGN KEY (AnimeID) REFERENCES Anime(AnimeID),  -- Khóa ngoại đến bảng Anime
    FOREIGN KEY (GenresID) REFERENCES Genres(GenresID)     -- Khóa ngoại đến bảng Genres
);
-- Tách và chèn dữ liệu vào bảng Anime_genres
INSERT INTO Anime_genres (AnimeID, GenresID)
SELECT 
    a.AnimeID,
    g.GenresID
FROM AnimeData a
CROSS APPLY STRING_SPLIT(a.Genres, ',') AS splitGenres
JOIN Genres g ON TRIM(splitGenres.value) = g.GenreName;

----- Tạo bảng Studio
CREATE TABLE Studio (
    StudioID INT IDENTITY(1,1) PRIMARY KEY,
    StudioName NVARCHAR(255) UNIQUE
);
--
CREATE TABLE Anime_Studio (
    SXID INT IDENTITY(1,1) PRIMARY KEY,
    AnimeID INT, -- Khóa ngoại từ bảng Anime
    StudioID INT, -- Khóa ngoại từ bảng Studio
    FOREIGN KEY (AnimeID) REFERENCES Anime(AnimeID), 
    FOREIGN KEY (StudioID) REFERENCES Studio(StudioID)
);
--
;WITH StudioCTE AS (
    SELECT DISTINCT TRIM(value) AS StudioName
    FROM AnimeData
    CROSS APPLY STRING_SPLIT(Studio, ',') -- Tách studio
)
INSERT INTO Studio(StudioName)
SELECT StudioName
FROM StudioCTE;
--
INSERT INTO Anime_Studio (AnimeID, StudioID)
SELECT a.AnimeID, s.StudioID
FROM AnimeData a
CROSS APPLY (
    SELECT TRIM(value) AS StudioName
    FROM STRING_SPLIT(a.Studio, ',')
) AS temp
JOIN Studio s ON temp.StudioName = s.StudioName;



