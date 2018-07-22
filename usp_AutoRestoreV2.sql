USE [master]
GO

/****** Object:  StoredProcedure [dbo].[usp_AutoRestoreV2]    Script Date: 21-07-2018 08:37:53 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE procedure [dbo].[usp_AutoRestoreV2] 
	@dbName sysname, 
	@backupPath nvarchar(500), 
	@serverName nvarchar(128), 
	@region nvarchar(12) = N'Not set', 
	@debug bit = 0, 
	@skipBackupDeletion bit = 0, 
	@FirstFailedDateAdd int = 0, 
	@LastFailedDateAdd int = 0, 
	@FailedRestoreCountSetting int = 0,
	@alternativeDataPath nvarchar(255) = N'',
	@alternativeLogPath nvarchar(255) = N'',
	@enableLogging bit = 0,
	@enableCheckDB bit = 0
AS
SET NOCOUNT ON 
-- 1 - Variable declaration 
DECLARE @cmd nvarchar(4000) 
DECLARE @fileList TABLE (backupFile nvarchar(255)) 
DECLARE @lastFullBackup nvarchar(500)
DECLARE @LastFullBackupDateTime nvarchar(35) 
DECLARE @lastDiffBackup nvarchar(500) 
DECLARE @LastDiffBackupDateTime nvarchar(35)
DECLARE @backupFile nvarchar(500)
DECLARE @LogicalName nvarchar(128)
DECLARE @PhysicalName nvarchar(128)
DECLARE @Counter int
DECLARE @ID int
DECLARE @MoveFile nvarchar(256)
DECLARE @Type nchar(1)
DECLARE @completeBackupPath nvarchar(500)
-- Variables for RerunBackupAndAlarming part
DECLARE @FailedRestoreCount int;
DECLARE @FirstFailedDate datetime2(0);
DECLARE @LastFailedDate datetime2(0);

BEGIN TRY
	IF(@dbName = N'master' OR  @dbName = N'model' OR @dbName = N'msdb' OR @dbName = N'tempdb')
	BEGIN
		RETURN
	END

	IF(RIGHT(@backupPath, 1) <> N'\')
	BEGIN
		SET @backupPath = @backupPath + N'\'
	END

	IF(LEN(@alternativeDataPath) > 0 AND (RIGHT(@alternativeDataPath, 1) <> N'\'))
	BEGIN
		SET @alternativeDataPath = @alternativeDataPath  + N'\'
	END

	IF(LEN(@alternativeLogPath) > 0 AND (RIGHT(@alternativeLogPath, 1) <> N'\'))
	BEGIN
		SET @alternativeLogPath = @alternativeLogPath  + N'\'
	END

	SET @completeBackupPath = @backupPath + @serverName + N'\' + @dbName + N'\'

	IF(LEN(@alternativeDataPath) < 1)
	BEGIN
		SET @alternativeDataPath = CONVERT(nvarchar(255), SERVERPROPERTY('InstanceDefaultDataPath'))
	END

	IF(LEN(@alternativeLogPath) < 1)
	BEGIN
		SET @alternativeLogPath = CONVERT(nvarchar(255), SERVERPROPERTY('InstanceDefaultLogPath'))
	END
	
	IF(LEN(@completeBackupPath + @dbName) < 230) 
	BEGIN
		IF(@enableLogging = 1)
		BEGIN
			-- RerunBackupAndAlarming - Check if last fails is passing threshold
			SELECT
				@FailedRestoreCount = FailedRestoreCount,
				@FirstFailedDate = FirstFailedDate,
				@LastFailedDate = LastFailedDate
			FROM master.monitoring.AutoRestoreMultiFailedDBs
			WHERE ServerName = @serverName 
				AND DatabaseName = @dbName

			IF ( @FailedRestoreCount < @FailedRestoreCountSetting
					AND @FirstFailedDate < DATEADD(DAY, @FirstFailedDateAdd, GETDATE()) -- indsæt variable til beregning
					AND @LastFailedDate < DATEADD(DAY, @LastFailedDateAdd, GETDATE())) -- indsæt variable til beregning
			BEGIN
				UPDATE master.monitoring.AutoRestoreMultiFailedDBs
					SET FirstFailedDate = NULL,
						LastFailedDate = NULL,
						FailedRestoreCount = 0
				WHERE ServerName = @serverName 
					AND DatabaseName = @dbName
			END

			-- Insert current running DB into table
			insert into master.monitoring.AutoRestoreCompletedDBs(DBName, LogDate, DBLength, BackupPath, servername, Region )
			values(@dbName,SYSDATETIMEOFFSET(), LEN(@completeBackupPath + @dbName), @completeBackupPath, @serverName, @region)

			-- If database exists in exclusion table, stop restore
			IF EXISTS (SELECT * FROM master.monitoring.AutoRestoreExclusions WHERE DatabaseName = @dbName and (ServerName is null or ServerName = N'')) OR 
			EXISTS (SELECT * FROM master.monitoring.AutoRestoreExclusions WHERE DatabaseName = @dbName and ServerName = @serverName) OR
			EXISTS (SELECT * FROM master.monitoring.AutoRestoreExclusions WHERE ServerName = @serverName and (DatabaseName is null or DatabaseName = N''))
			BEGIN
				RETURN
			END
		END

		DECLARE @Table TABLE (ID int identity(1,1) primary key,LogicalName nvarchar(128),[PhysicalName] nvarchar(192), [Type] nvarchar, [FileGroupName] nvarchar(128), [Size] nvarchar(128), 
					[MaxSize] nvarchar(128), [FileId] nvarchar(128), [CreateLSN] nvarchar(128), [DropLSN] nvarchar(128), [UniqueId] nvarchar(128), [ReadOnlyLSN] nvarchar(128), [ReadWriteLSN] nvarchar(128), 
					[BackupSizeInBytes] nvarchar(128), [SourceBlockSize] nvarchar(128), [FileGroupId] nvarchar(128), [LogGroupGUID] nvarchar(128), [DifferentialBaseLSN] nvarchar(128), [DifferentialBaseGUID] nvarchar(128), [IsReadOnly] nvarchar(128), [IsPresent] nvarchar(128), [TDEThumbprint] nvarchar(128), SnapshotURL nvarchar(360)
		)

		DECLARE @MoveFiles TABLE (ID int identity(1,1) primary key,moveFile nvarchar(256))

		-- 2. Get list of files 
		SET @cmd = 'DIR /b ' + @completeBackupPath + 'FULL\'

		INSERT INTO @fileList(backupFile) 
		EXEC master.sys.xp_cmdshell @cmd 

		SET @cmd = 'DIR /b ' + @completeBackupPath + 'DIFF\'

		INSERT INTO @fileList(backupFile) 
		EXEC master.sys.xp_cmdshell @cmd 

		SET @cmd = 'DIR /b ' + @completeBackupPath + 'LOG\'

		INSERT INTO @fileList(backupFile) 
		EXEC master.sys.xp_cmdshell @cmd 

		-- 3. Find latest full backup 
		SELECT @lastFullBackup = MAX(backupFile)  
		FROM @fileList  
		WHERE backupFile LIKE '%.BAK'  
		   AND backupFile LIKE + '%' + @dbName + '%'
		   AND backupFile like '%FULL%'
		
		-- 4. Get database logical filenames
		INSERT INTO @table
		EXEC('
		RESTORE FILELISTONLY 
		   FROM DISK=''' + @completeBackupPath + 'FULL\' + @lastFullBackup + '''
		   ')
		   
		SET @Counter = (select count(*) from @Table)
		   			
		WHILE @Counter > 0
		BEGIN			
			SELECT @ID=ID, @LogicalName=LogicalName, @Type = [Type], @PhysicalName= right(PhysicalName,(len(PhysicalName) - len(SUBSTRING(physicalname,1, LEN(physicalname) - CHARINDEX('\', REVERSE(physicalname)) +1)))) FROM @Table ORDER BY ID DESC
			DELETE FROM @Table WHERE ID=@ID
					

			IF(@Type = N'D')
			BEGIN
				insert into @MoveFiles(moveFile)
				values((', move ''' + @LogicalName + ''' to ''' + @alternativeDataPath + @PhysicalName + ''''))
			END

			IF(@Type = N'L')
			BEGIN
				insert into @MoveFiles(moveFile)
				values((', move ''' + @LogicalName + ''' to ''' + @alternativeLogPath + @PhysicalName + ''''))
			END

			SET @Counter = @Counter - 1
		END 

			SET @LastFullBackupDateTime = right(@lastFullBackup,len(@lastFullBackup) - (len(@lastFullBackup) - 19))
			SET @cmd = 'RESTORE DATABASE [' + @dbName + '] FROM DISK = '''  
				   + @completeBackupPath + 'FULL\' + @lastFullBackup + ''' WITH NORECOVERY, REPLACE'
			
			SET @Counter = (select COUNT(*) from @MoveFiles)
			WHILE @Counter > 0
			BEGIN
				SELECT @ID=ID, @MoveFile=movefile FROM @MoveFiles ORDER BY ID DESC
				SET @cmd += @MoveFile
				DELETE FROM @MoveFiles WHERE ID=@ID
				SET @MoveFile = ''
				SET @Counter = @Counter - 1
			END	  

			IF(@debug = 1)
			BEGIN
				PRINT @cmd 
			END
			ELSE
			BEGIN
				EXEC sp_executesql @cmd
			END

			-- 6. Find latest diff backup 
			SELECT @lastDiffBackup = MAX(backupFile)  
			FROM @fileList  
			WHERE backupFile LIKE + '%' + @dbName + '%' 
			   AND right(backupFile,len(backupFile) - (len(backupFile) - 19)) > @LastFullBackupDateTime
			   AND backupFile like '%DIFF%'
			-- check to make sure there is a diff backup 
			IF @lastDiffBackup IS NOT NULL 
			BEGIN 
			   SET @cmd = 'RESTORE DATABASE [' + @dbName + '] FROM DISK = '''  
				   + @completeBackupPath + 'DIFF\' + @lastDiffBackup + ''' WITH NORECOVERY'
			   	IF(@debug = 1)
				BEGIN
					PRINT @cmd 
				END
				ELSE
				BEGIN
					EXEC sp_executesql @cmd
				END
			   SET @LastDiffBackupDateTime = RIGHT(@lastDiffBackup,len(@lastDiffBackup) - (len(@lastDiffBackup) - 19))
			END 

			-- 7. Check for log backups 
			DECLARE backupFiles CURSOR FOR  
			   SELECT backupFile  
			   FROM @fileList 
			   WHERE backupFile LIKE '%.TRN'  
			   AND backupFile LIKE + '%' + @dbName + '%' 
			   AND right(backupFile,len(backupFile) - (len(backupFile) - 19)) > @LastDiffBackupDateTime 
			   AND backupFile like '%LOG%'
			   order by backupFile asc

			OPEN backupFiles  

			-- Loop through all the files for the database  
			FETCH NEXT FROM backupFiles INTO @backupFile  

			WHILE @@FETCH_STATUS = 0  
			BEGIN  
			   SET @cmd = 'RESTORE LOG [' + @dbName + '] FROM DISK = '''  
				   + @completeBackupPath + 'LOG\' + @backupFile + ''' WITH NORECOVERY' 
			   	
				IF(@debug = 1)
				BEGIN
					PRINT @cmd 
				END
				ELSE
				BEGIN
					EXEC sp_executesql @cmd
				END

			   FETCH NEXT FROM backupFiles INTO @backupFile  
			END 

			IF CURSOR_STATUS('global','backupFiles')>=-1
			BEGIN
				CLOSE backupFiles  
				DEALLOCATE backupFiles  
			END
			
		--END -- Else/if statement END (5. If not in exclusion table, restore)
	END -- if statement END (LEN(@completeBackupPath) < 230)
END TRY

BEGIN CATCH
	IF(@enableLogging = 1)
		BEGIN
		-- RerunBackupAndAlarming - If database exists in multifailed table then update it, if not then create it with updated values 
		IF EXISTS (SELECT 1 FROM master.monitoring.AutoRestoreMultiFailedDBs WHERE ServerName = @serverName AND DatabaseName = @dbName)
		BEGIN
			IF NOT EXISTS (SELECT 1 FROM master.monitoring.AutoRestoreMultiFailedDBs WHERE ServerName = @serverName AND DatabaseName = @dbName AND TRY_CAST(LastFailedDate AS date) = TRY_CAST(GETDATE() AS date))
			BEGIN
				UPDATE master.monitoring.AutoRestoreMultiFailedDBs
					SET FailedRestoreCount = FailedRestoreCount + 1,
						BackupRerunNeeded = 1,
						LastFailedDate = GETDATE(),
						FirstFailedDate = CASE WHEN FirstFailedDate IS NULL THEN GETDATE() ELSE FirstFailedDate END,
						BackupPath = @backupPath
				WHERE ServerName = @serverName
					AND DatabaseName = @dbName
			END
		END
		ELSE
		BEGIN
			INSERT INTO master.monitoring.AutoRestoreMultiFailedDBs(ServerName, DatabaseName, FailedRestoreCount, BackupRerunNeeded, LastFailedDate, FirstFailedDate, BackupPath)
			VALUES(@serverName, @dbName, 1, 1, GETDATE(), GETDATE(), @backupPath)
		END

		-- If failed more than @FailedRestoreCountSetting, then put in results table
		IF (
			EXISTS(SELECT 1 FROM master.monitoring.AutoRestoreMultiFailedDBs WHERE ServerName = @serverName AND DatabaseName = @dbName AND FailedRestoreCount > 3) OR
			EXISTS(SELECT 1 WHERE @LastFailedDateAdd = 0 AND @FirstFailedDateAdd = 0))
		BEGIN
			INSERT INTO master.monitoring.AutoRestoreResults (
				DatabaseName,
				ErrorNumber,
				ErrorSeverity,
				ErrorState,
				ErrorProcedure,
				ErrorLine,
				ErrorMessage,
				BackupPath,
				LogDate,
				Region ) 
			VALUES (
				@dbName,
				ERROR_NUMBER(),
				ERROR_SEVERITY(),
				ERROR_STATE(),
				ERROR_PROCEDURE(),
				ERROR_LINE(),
				ERROR_MESSAGE(),
				@completeBackupPath,
				SYSDATETIMEOFFSET(),
				@region )

			-- Temp test
			SELECT
				ERROR_NUMBER(),
				ERROR_SEVERITY(),
				ERROR_STATE(),
				ERROR_PROCEDURE(),
				ERROR_LINE(),
				ERROR_MESSAGE(),
				GetDate()
		END
	END

	-- If run manually, print error message
	SELECT
		ERROR_NUMBER(),
		ERROR_SEVERITY(),
		ERROR_STATE(),
		ERROR_PROCEDURE(),
		ERROR_LINE(),
		ERROR_MESSAGE(),
		GetDate()
		
	-- Drop database when done
	IF EXISTS (
		SELECT name FROM master.dbo.sysdatabases 
		WHERE ('[' + name + ']' = @dbName OR name = @dbName))
		AND @dbName <> 'master'
		AND @dbname <> 'msdb'
		AND @dbName <> 'model'
		AND @dbName <> 'tempdb'
		AND @skipBackupDeletion <> 1
	EXEC ('DROP DATABASE ' + @dbName)
	
	IF CURSOR_STATUS('global','backupFiles')>=-1
	BEGIN
		CLOSE backupFiles  
		DEALLOCATE backupFiles  
	END

END CATCH 

-- 8. Put database in a useable state 
---- NOTE: WHEN RESTORING A DATABASE, TRY/CATCH CAN CATCH INTERNAL RECOVERY ERRORS AND THROW EXCEPTION, WHICH NORMALLY DOESN'T AFFECT THE RESTORE
SET @cmd = 'RESTORE DATABASE [' + @dbName + '] WITH RECOVERY' 
			
IF(@debug = 1)
BEGIN
	PRINT @cmd 
END
ELSE
BEGIN
	IF EXISTS (
		SELECT name FROM master.dbo.sysdatabases 
		WHERE ('[' + name + ']' = @dbName OR name = @dbName))
	BEGIN
		EXEC sp_executesql @cmd
	END
END
---- NOTE: WHEN RESTORING A DATABASE, TRY/CATCH CAN CATCH INTERNAL RECOVERY ERRORS AND THROW EXCEPTION, WHICH NORMALLY DOESN'T AFFECT THE RESTORE

-- 9. Run CHECKDB against the restored database
IF(@enableCheckDB = 1)
BEGIN
	BEGIN TRY
		-- Check if database exists before running checkdb
		IF (EXISTS (
			SELECT name 
			FROM master.dbo.sysdatabases 
			WHERE ('[' + name + ']' = @dbName 
				OR name = @dbName)))
		BEGIN
			-- Variables for storing DBCC starttime, endtime and total running minutes
			DECLARE @CheckDBStartTime datetime2, @CheckDBEndTime datetime2, @TotalRuntimeMinutes int;

			-- Table variable for temp storage of DBCC output
			DECLARE @tmpCheckDBErrors TABLE(
				Error int NULL,
				Level int NULL,
				State int NULL,
				MessageText varchar(7000) NULL,
				RepairLevel int NULL,
				Status int NULL,
				DbId int NULL,
				DbFragId int NULL,
				ObjectId int NULL,
				IndId int NULL,
				PartitionID int NULL,
				AllocUnitID int NULL,
				RidDbId int NULL,
				RidPruId int NULL,
				[File] int NULL,
				Page int NULL,
				Slot int NULL,
				RefDbId int NULL,
				RedPruId int NULL,
				RefFile int NULL,
				RefPage int NULL,
				RefSlot int NULL,
				Allocation int NULL
			);

			-- Set CHECKDB starttime
			SET @CheckDBStartTime = GETDATE();

			-- Run CHECKDB command and insert into temp table variable
			INSERT INTO @tmpCheckDBErrors(
				[Error], 
				[Level], 
				[State], 
				MessageText, 
				RepairLevel, 
				[Status], 
				[DbId], 
				DbFragId,
				ObjectId,
				IndId, 
				PartitionId, 
				AllocUnitId, 
				RidDbId,
				RidPruId,
				[File], 
				[Page], 
				Slot, 
				RefDbId,
				RedPruId,
				RefFile, 
				RefPage, 
				RefSlot,
				Allocation)
			EXEC ('dbcc checkdb([' + @dbName + ']) with no_infomsgs, all_errormsgs, tableresults');

			-- Set CHECKDB endtime
			SET @CheckDBEndTime = GETDATE();

			IF(@enableLogging = 1)
			BEGIN
				-- Insert CHECKDB message text into management database, including some identification data
				INSERT INTO master.monitoring.CheckDBErrors(
					DatabaseName,
					ServerName,
					CheckDBMessageText,
					Region)
				SELECT 
					@dbName,
					@serverName,
					MessageText,
					@region
				FROM @tmpCheckDBErrors

				-- Calculate total runtime in minutes for CHECKDB
				SET @TotalRuntimeMinutes = DATEDIFF(MINUTE, @CheckDBStartTime, @CheckDBEndTime);

				-- Check, just to avoid zeroes when doing calculations and CHECKDB has actually run
				IF (@TotalRuntimeMinutes < 1)
				BEGIN
					SET @TotalRuntimeMinutes = 1;
				END

				-- If row exists for database on server, then update row. If not, create new row.
				IF EXISTS(SELECT 1 FROM master.monitoring.CheckDBHistory WHERE DatabaseName = @dbName AND ServerName = @serverName) 
				BEGIN
					DECLARE @ShortestRun INT, @LongestRun INT, @AverageRun DECIMAL(8,3), @NumberOfRuns INT, @CheckDBId INT;

					-- Get existing data for manipulation
					SELECT
						@CheckDBId = Id,
						@ShortestRun = ShortestRunMinutes,
						@LongestRun = LongestRunMinutes,
						@AverageRun = AverageRunMinutes,
						@NumberOfRuns = NumberOfRuns
					FROM 
						master.monitoring.CheckDBHistory
					WHERE
						DatabaseName = @dbName 
						AND ServerName = @serverName;

					-- Check if run is shorter than currently shortest run
					IF (@TotalRuntimeMinutes < @ShortestRun)
					BEGIN
						SET @ShortestRun = @TotalRuntimeMinutes;
					END

					-- Check if run is longer than currently longest run
					IF (@TotalRuntimeMinutes > @LongestRun)
					BEGIN
						SET @LongestRun = @TotalRuntimeMinutes;
					END

					-- Calculate average runtime
					SET @AverageRun = ((@AverageRun * @NumberOfRuns) + @TotalRuntimeMinutes) / (@NumberOfRuns + 1);

					-- Update row with recalculated data
					UPDATE master.monitoring.CheckDBHistory
					SET ShortestRunMinutes = @ShortestRun,
						LongestRunMinutes = @LongestRun,
						AverageRunMinutes = @AverageRun,
						NumberOfRuns = @NumberOfRuns + 1,
						LatestRun = GETDATE()
					WHERE Id = @CheckDBId
				END
			END
			ELSE
			BEGIN
				IF(@enableLogging = 1)
				BEGIN
					INSERT INTO master.monitoring.CheckDBHistory(
						DatabaseName,
						ServerName,
						ShortestRunMinutes,
						LongestRunMinutes,
						AverageRunMinutes,
						NumberOfRuns,
						LatestRun,
						Region)
					VALUES(
						@dbName,
						@serverName,
						@TotalRuntimeMinutes,
						@TotalRuntimeMinutes,
						@TotalRuntimeMinutes,
						1,
						@CheckDBStartTime,
						@region)
				END
			END
		END
	END TRY
	BEGIN CATCH
		IF(@enableLogging = 1)
		BEGIN
			INSERT INTO master.monitoring.CheckDBErrors(
				DatabaseName,
				ServerName,
				CheckDBMessageText,
				ErrorMessage,
				Region)
			SELECT 
				@dbName,
				@serverName,
				'Couldn''t run CHECKDB on this database',
				ERROR_MESSAGE(),
				@region
		END
	END CATCH
END

BEGIN TRY

	-- 10. Drop database when done
	IF EXISTS (
		SELECT name FROM master.dbo.sysdatabases 
		WHERE ('[' + name + ']' = @dbName OR name = @dbName)) 
		AND @dbName <> 'master'
		AND @dbname <> 'msdb'
		AND @dbName <> 'model'
		AND @dbName <> 'tempdb'
		AND @skipBackupDeletion <> 1
	EXEC ('DROP DATABASE [' + @dbName +']')
END TRY
BEGIN CATCH
	IF(@enableLogging = 1)
	BEGIN
		-- RerunBackupAndAlarming - If database exists in multifailed table then update it, if not then create it with updated values 
		IF EXISTS (SELECT 1 FROM master.monitoring.AutoRestoreMultiFailedDBs WHERE ServerName = @serverName AND DatabaseName = @dbName)
		BEGIN
			IF NOT EXISTS (SELECT 1 FROM master.monitoring.AutoRestoreMultiFailedDBs WHERE ServerName = @serverName AND DatabaseName = @dbName AND TRY_CAST(LastFailedDate AS date) = TRY_CAST(GETDATE() AS date))
			BEGIN
				UPDATE master.monitoring.AutoRestoreMultiFailedDBs
					SET FailedRestoreCount = FailedRestoreCount + 1,
						BackupRerunNeeded = 1,
						LastFailedDate = GETDATE(),
						FirstFailedDate = CASE WHEN FirstFailedDate IS NULL THEN GETDATE() ELSE FirstFailedDate END,
						BackupPath = @backupPath
				WHERE ServerName = @serverName
					AND DatabaseName = @dbName
			END
		END
		ELSE
		BEGIN
			INSERT INTO master.monitoring.AutoRestoreMultiFailedDBs(ServerName, DatabaseName, FailedRestoreCount, BackupRerunNeeded, LastFailedDate, FirstFailedDate, BackupPath)
			VALUES(@serverName, @dbName, 1, 1, GETDATE(), GETDATE(), @backupPath)
		END

		-- If failed more than 3 times, then put in results table
		IF EXISTS (SELECT 1 FROM master.monitoring.AutoRestoreMultiFailedDBs WHERE ServerName = @serverName AND DatabaseName = @dbName AND FailedRestoreCount > 3)
		BEGIN
			insert into master.monitoring.AutoRestoreResults (
				DatabaseName,
				ErrorNumber,
				ErrorSeverity,
				ErrorState,
				ErrorProcedure,
				ErrorLine,
				ErrorMessage,
				BackupPath,
				LogDate,
				Region ) 
			VALUES (
				@dbName,
				ERROR_NUMBER(),
				ERROR_SEVERITY(),
				ERROR_STATE(),
				ERROR_PROCEDURE(),
				ERROR_LINE(),
				ERROR_MESSAGE(),
				@completeBackupPath,
				SYSDATETIMEOFFSET(),
				@region )

		-- If run manually, print error message
		SELECT
			ERROR_NUMBER(),
			ERROR_SEVERITY(),
			ERROR_STATE(),
			ERROR_PROCEDURE(),
			ERROR_LINE(),
			ERROR_MESSAGE(),
			GetDate()
		END
	END
END CATCH


GO


