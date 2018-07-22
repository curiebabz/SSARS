What is SSARS?
SQL Server Auto Restore Script is a help to anyone making use of Ola Hallengren’s backup solution and who wants to add a backup test layer on top of this. In the environment at my current employer, I have noticed some databases being backed up by unknown backup software, applications or manually by users on a regular basis, rendering your own efforts worthless. Hopefully this can help you identify any issues and make sure you are able to recover databases when disaster strikes.
AutoRestore server
Use either a dedicated instance or a dedicated server; the latter being the recommended approach. The most important thing is that there is enough storage to accommodate restore of the biggest database.
Monitoring tables
If you want to make use of the logging functionality, you need to create the tables provided in the database.sql file. The AutoRestore script assumes that the master database on the AutoRestore server will be used.

If you are utilizing a CMS server or a central management database, you could consider making use of this database. This would require you to configure linked server on the AutoRestore server as well as changing the parts in the AutoRestore script to point at this server and database for all monitoring.* tables.

monitoring.AutoRestoreCompletedDBs
Logs every database restore
monitoring.AutoRestoreExclusions
Exclude a database or a complete server from being tested, see exclude section
monitoring.AutoRestoreMultiFailedDBs
Logs if a database restore has failed multiple times, see FixBackupChain section
monitoring.AutoRestoreResults
Shows all failed databases which meets logging criteria, see FixBackupChain section
monitoring.CheckDBErrors
Logs all errors during CheckDB
monitoring.CheckDBHistory
Logs all databases that CheckDB has checked
monitoring.AutoRestoreExclusions
This table can be used to exclude restore testing of a single database, a complete server or, if a database exists on multiple servers with the same name, a specific database on a specific server.

Exclude database
Only add the database name in the DatabaseName column, ServerName column should be NULL
Exclude server
Only add the server name in the ServerName column, DatabaseName column should be NULL
Exclude database on specific server only
Add database name AND server name in the respective columns
AutoRestore procedure
This is the procedure that does everything on the AutoRestore server. If you don’t want to use any other feature except restore databases, through T-SQL or Powershell, this is the only thing you really need. The procedure only restores one database. If you want to restore multiple databases, use the Powershell script to loop through all database folders.
Deployment
To deploy the script, simply execute the usp_AutoRestoreV2.sql file on the AutoRestore server which will create a stored procedure in the default location, being master database - change it if you’d like.

Xp_cmdshell needs to be enabled on the AutoRestore server in order for the stored procedure to work.
Parameters
Here is a short description of parameters and their usage.
For reference below, this is the fictional backup location for a specific database that we want to restore: \\storage\sqlBackups\serverName\databaseName

dbName (sysname)
Name of database being restored, \\storage\sqlBackups\serverName\databaseName
backupPath (nvarchar(500)) 
The root path for all database backups, \\storage\sqlBackups\serverName\databaseName
serverName (nvarchar(128))
Name of server where database was backed up from, \\storage\sqlBackups\serverName\databaseName
region (nvarchar(12), default value N'Not set’)
If you have multiple locations with AutoRestore servers in each, and are using a CMS server or management database, this value can be used to indicate which location a restore failure has occurred
debug (bit, default value 0) 
When set to 1, it prints out the whole restore T-SQL command, useful for debugging a database restore failure or to prepare a complete restore of a database to be used on another server
skipBackupDeletion (bit, default value 0)
Skips deletion of databases after restore
FirstFailedDateAdd (int, default value 0) 
Used in logging function for another script, fixBackupChain. Description in FixBackupChain section
LastFailedDateAdd (int, default value 0)
Used in logging function for another script, fixBackupChain. Description in FixBackupChain section
FailedRestoreCountSetting (int, default value 0)
Used in logging function for another script, fixBackupChain. Description in FixBackupChain section
alternativeDataPath (nvarchar(255), default value N'')
Specify different location to restore datafiles instead of the data folder specified during SQL Server installation 
alternativeLogPath (nvarchar(255), default value N'')
Specify different location to restore logfiles instead of the log folder specified during SQL Server installation
enableLogging (bit, default value 0)
When set to 1, starts logging data to monitoring.* tables
enableCheckDB (bit, default value 0)
When set to 1, runs CheckDB after a database has been restored
Automation
Below is a description how to automate the process of testing all databases from a storage location
Powershell
The Powershell script is fairly simple, simply looping through all server folders and get the database subfolder names, then execute the AutoRestore procedure for each database folder.

You need to give a couple of parameters.
$path
Root path for backup storage, e.g. "\\storage\Backups"
$autoRestoreServer
The AutoRestore server, e.g. "AutoRestore\Inst01"
$autoRestoreSPDatabase
The database where AutoRestore procedure is created, e.g. "master"

To add a parameter that should be included when the stored procedure is executed, add a line to the Powershell script.
$cmd.Parameters.Add("@enableCheckDB","1") | out-Null
SQL Agent
Create a SQL Agent job which executes a Powershell task and insert the Powershell script here. 

Proxy account
Create a service account* and grant it the necessary permissions.

Access to backup storage
Sysadmin on the AutoRestore server
This is required by CheckDB, but if you’re not going to use it then you can play around with more strict permissions

Next, create credentials using the service account created earlier, and then a SQL Agent Powershell proxy account using the new credentials. Edit the SQL Agent job and set the new proxy account to be the run as account.

* In my mind, an Active Directory user with minimal permissions following your corporations standards.
FixBackupChain
monitoring.AutoRestoreMultiFailedDBs
This table is mainly used if you want to utilize the FixBackupChain procedure or if you think it’s okay that databases fail more than once. If this is irrelevant to use, simply let the the parameters, FirstFailedDateAdd and LastFailedDateAdd, keep their default values.

When the AutoRestore script tests a database and it fails, it will be logged here. If there’s no entry for the database then it will be created, if it exists it will update the entry.

The FailedRestoreCount column indicates how many times the backup has failed
BackupRerunNeeded indicates if a new full backup is needed. This will be set to 1 if a test fails and will be used by the FixBackupChain procedure.
LastFailedDate shows the last time a test has failed
FirstFailedDate shows the first time a test has failed

There are 3 procedure parameters that is related to this part.

FirstFailedDateAdd
Used in calculation for when FirstFailedDate column is older than today minus FirstFailedDateAdd. This should be a negative number, measured in days.
LastFailedDateAdd
Used in calculation for when LastFailedDate column is older than today minus LastFailedDateAdd. This should be a negative number, measured in days
FailedRestoreCountSetting
How many times a backup test fails before reported to monitoring.AutoRestoreResults

Example - reset mechanism at the start of the script
IF FailedRestoreCount in the table is less than @FailedRestoreCountSetting AND
FirstFailedDate in the table is older than DATEADD(DAY, @FirstFailedDateAdd) AND
LastFailedDate in table is older than DATEADD(DAY, @LastFailedDateAdd) THEN
reset counters in table

Example - if failed tests passes threshold
IF FailedRestoreCount in the table is bigger than @FailedRestoreCountSetting THEN
INSERT into monitoring.AutoRestoreResults

Example - instanty report failed tests
If FirstFailedDateAdd equal 0  AND
LastFailedDateAdd equal 0 THEN
INSERT into monitoring.AutoRestoreResults

How to use FirstFailedDateAdd, LastFailedDateAdd and FailedRestorecountSetting parameters
These two parameters are used to calculate the age of failed backups to test against the threshold set. In this example we want to report on databases that has failed more than 2 times within the last 5 days but but no later than 2 days ago then we would set the parameters as:

FirstFailedDateAdd = 2
LastFailedDateAdd = 5
FailedRestoreCountSetting = 2

monitoring.AutoRestoreResults
This table contains the failed database tests that surpasses the threshold specified above, which means that the entries in this table should be the ones being taken care of. This could indicate something is consistently breaking the backup chain, being unknown backup software or users doing manual backups regularly.

Based on the entries in this table, you could configure mail notification to any backup operators or admins which should take a look at this and try to fix it.

FixBackupChain procedure
The procedure simply looks in the monitoring.AutoRestoreMultiFailedDBs and checks if there are any databases for the server that needs to be backed up, if there are then it runs a full backup and updates the column BackupRerunNeeded to 0.

The procedure assumes there is a linked server called autorestoreserver which has access to the monitoring.AutoRestoreMultiFailedDBs table. If you are using a CMS server, then this should be the servername in the linked server.

It also assumes that the Ola Hallengren backup procedure is located in the master database of the SQL Server. Lastly, just create a SQL Agent job that executes the FixBackupChain procedure and you should be all done.
			

