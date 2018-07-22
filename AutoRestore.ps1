$path = "\\storage\Backups"
$autoRestoreServer = "sqlmgmt01\bkptst"
$autoRestoreSPDatabase = "master"

# WORKAROUND
C:
#WORKAROUND 

$connectionString = "Server=" + $autoRestoreServer + ";DataBase=" + $autoRestoreSPDatabase + ";Integrated Security=SSPI"

$Folders = Get-ChildItem -Path $path
$serverPath = ""

$conn = new-Object System.Data.SqlClient.SqlConnection($connectionString)
$conn.Open() | out-null 

ForEach ($Folder in $Folders)
{
  $serverPath = $path + "\" + $Folder
  $childFolders = Get-ChildItem -Path $serverPath

  ForEach ($childFolder in $childFolders)
  {   
    try {
      $cmd = new-Object System.Data.SqlClient.SqlCommand("usp_AutoRestoreV2", $conn)
      $cmd.CommandType = [System.Data.CommandType]'StoredProcedure'

      # Override normal timeout, or else it will timeout if restore takes more than 30 seconds
      $cmd.CommandTimeout = 0

      # This Parameter Line This will error if Parameters are not accepted by Stored Procedure.
      $cmd.Parameters.Add("@dbName",[string]$childFolder) | out-Null 

      # This Parameter Line This will error if Parameters are not accepted by Stored Procedure.
      $cmd.Parameters.Add("@servername",[string]$Folder) | out-Null 

      # This Parameter Line This will error if Parameters are not accepted by Stored Procedure.
      $cmd.Parameters.Add("@backupPath",[string]$path) | out-Null 

      $cmd.ExecuteNonQuery()

    } catch { }
  }

  $serverPath = ""
}
