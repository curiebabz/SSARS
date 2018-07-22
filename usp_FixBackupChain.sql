USE [master]
GO

/****** Object:  StoredProcedure [dbo].[usp_fixBackupChain]    Script Date: 21-07-2018 18:10:49 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_fixBackupChain]
AS

-- Declare variables
DECLARE @result nvarchar(max);
DECLARE @backupPath nvarchar(max);
DECLARE @serverNames TABLE (
	serverName nvarchar(32) COLLATE Latin1_General_100_CI_AS
)

-- Convert hostname to Ola Hallengren servername/root backup folder standard
INSERT INTO @serverNames(serverName)
SELECT REPLACE(CAST(SERVERPROPERTY('ServerName') AS nvarchar(32)),N'\',N'$') COLLATE Latin1_General_100_CI_AS;

-- Check if version is too old or HADR isn't enabled 
IF (CAST((SELECT SERVERPROPERTY('ProductMajorVersion')) AS int) <> 10 AND CAST((SELECT SERVERPROPERTY('IsHadrEnabled')) AS int) = 1)
BEGIN
	-- Insert any availability groups, converted to Ola Hallengren servername/root backup folder standard
	INSERT INTO @serverNames(serverName)
	SELECT cluster_name + N'$' + [name] COLLATE Latin1_General_100_CI_AS
	FROM sys.dm_hadr_cluster AS c, sys.availability_groups AS ag
		INNER JOIN sys.dm_hadr_availability_group_states AS ags
			ON ag.group_id = ags.group_id
	WHERE ags.primary_replica = CAST(SERVERPROPERTY('ServerName') AS nvarchar(32))
END

-- Create list of databases that needs to be backed up
SELECT @result = STUFF((SELECT N',' + CONVERT(nvarchar(32), DatabaseName)
					FROM autorestoreserver.master.monitoring.AutoRestoreMultiFailedDBs WHERE ServerName IN (SELECT ServerName FROM @serverNames) AND BackupRerunNeeded = 1
					FOR xml path('')),
					1,
					1,
					'');

-- Get backup path
SELECT TOP 1
	@backupPath = BackupPath 
FROM autorestoreserver.master.monitoring.AutoRestoreMultiFailedDBs 
WHERE ServerName IN (SELECT serverName FROM @serverNames);

-- Check if @result var is not null, if not then backup databases and update rerun table on management server
IF (@result IS NOT NULL)
BEGIN
	EXECUTE dbo.DatabaseBackup 
	 @Databases = @result, 
	 @Directory = @backupPath,
	 @BackupType = 'FULL',
	 @Verify = 'N',
	 @Compress = 'N',
	 @CheckSum = 'Y',
	 @LogToTable='Y', 
	 @CleanupTime='720'   


	 UPDATE autorestoreserver.master.monitoring.AutoRestoreMultiFailedDBs
	 SET BackupRerunNeeded = 0
	 WHERE ServerName IN (SELECT ServerName FROM @serverNames)
END
GO


