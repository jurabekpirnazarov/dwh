-- Jadval ustunlari profili. mssql_bak.sh profile orqali chaqiriladi, $(tbl) = sxema.jadval
SET NOCOUNT ON;
DECLARE @t nvarchar(300) = N'$(tbl)', @sql nvarchar(max), @c sysname, @n int;

IF OBJECT_ID(@t) IS NULL
BEGIN
    RAISERROR('Jadval topilmadi: %s', 16, 1, @t);
    RETURN;
END

PRINT '=== ' + @t + ': ustunlar profili ===';
-- Har ustun uchun bitta SELECT, hammasi UNION ALL bilan yig'iladi
SELECT @sql = STRING_AGG(CAST(
    'SELECT ' + CAST(c.column_id AS varchar(10)) + ' AS n, ''' + REPLACE(c.name, '''', '''''') + ''' AS ustun, '
    + 'CAST(100.0 * SUM(CASE WHEN NULLIF(LTRIM(RTRIM(CAST(' + QUOTENAME(c.name) + ' AS nvarchar(4000)))), '''') IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS decimal(5,1)) AS toldirilgan_foiz, '
    + 'COUNT(DISTINCT CAST(' + QUOTENAME(c.name) + ' AS nvarchar(4000))) AS noyob, '
    + 'LEFT(MIN(CAST(' + QUOTENAME(c.name) + ' AS nvarchar(4000))), 40) AS eng_kichik, '
    + 'LEFT(MAX(CAST(' + QUOTENAME(c.name) + ' AS nvarchar(4000))), 40) AS eng_katta '
    + 'FROM ' + @t AS nvarchar(max)), ' UNION ALL ') WITHIN GROUP (ORDER BY c.column_id)
FROM sys.columns c WHERE c.object_id = OBJECT_ID(@t);
SET @sql = 'SELECT ustun, toldirilgan_foiz, noyob, eng_kichik, eng_katta FROM (' + @sql + ') x ORDER BY n';
EXEC sp_executesql @sql;

PRINT '';
PRINT '=== Kam qiymatli ustunlar: taqsimot (noyob <= 30) ===';
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.columns WHERE object_id = OBJECT_ID(@t) ORDER BY column_id;
OPEN cur;
FETCH NEXT FROM cur INTO @c;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = 'SELECT @n = COUNT(DISTINCT CAST(' + QUOTENAME(@c) + ' AS nvarchar(4000))) FROM ' + @t;
    EXEC sp_executesql @sql, N'@n int OUTPUT', @n = @n OUTPUT;
    IF @n BETWEEN 1 AND 30
    BEGIN
        PRINT '';
        PRINT '-- ' + @c;
        SET @sql = 'SELECT CAST(' + QUOTENAME(@c) + ' AS nvarchar(60)) AS qiymat, COUNT(*) AS soni '
                 + 'FROM ' + @t + ' GROUP BY ' + QUOTENAME(@c) + ' ORDER BY COUNT(*) DESC';
        EXEC sp_executesql @sql;
    END
    FETCH NEXT FROM cur INTO @c;
END
CLOSE cur;
DEALLOCATE cur;
GO
