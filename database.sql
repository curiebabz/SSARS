USE [master]
GO
/****** Object:  Schema [monitoring]    Script Date: 03-05-2018 13:37:48 ******/
CREATE SCHEMA [monitoring]
GO
/****** Object:  Table [monitoring].[AutoRestoreCompletedDBs]    Script Date: 03-05-2018 13:37:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [monitoring].[AutoRestoreCompletedDBs](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DBName] [nvarchar](155) NULL,
	[LogDate] [datetimeoffset](2) NULL,
	[DBLength] [int] NULL,
	[BackupPath] [nvarchar](500) NULL,
	[ServerName] [nvarchar](128) NULL,
	[Region] [nvarchar](12) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [monitoring].[AutoRestoreExclusions]    Script Date: 03-05-2018 13:37:49 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [monitoring].[AutoRestoreExclusions](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DatabaseName] [nvarchar](75) NULL,
	[ServerName] [nvarchar](128) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [monitoring].[AutoRestoreMultiFailedDBs]    Script Date: 03-05-2018 13:37:49 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [monitoring].[AutoRestoreMultiFailedDBs](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[ServerName] [nvarchar](64) NULL,
	[DatabaseName] [nvarchar](64) NULL,
	[FailedRestoreCount] [int] NULL,
	[BackupRerunNeeded] [bit] NULL,
	[LastFailedDate] [datetime2](0) NULL,
	[FirstFailedDate] [datetime2](0) NULL,
	[BackupPath] [nvarchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
 CONSTRAINT [uc_ServDb] UNIQUE NONCLUSTERED 
(
	[ServerName] ASC,
	[DatabaseName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [monitoring].[AutoRestoreResults]    Script Date: 03-05-2018 13:37:49 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [monitoring].[AutoRestoreResults](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DatabaseName] [nvarchar](75) NULL,
	[ErrorNumber] [int] NULL,
	[ErrorSeverity] [int] NULL,
	[ErrorState] [int] NULL,
	[ErrorProcedure] [nvarchar](max) NULL,
	[ErrorLine] [int] NULL,
	[ErrorMessage] [nvarchar](max) NULL,
	[BackupPath] [nvarchar](max) NULL,
	[LogDate] [datetimeoffset](2) NULL,
	[Region] [nvarchar](12) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [monitoring].[CheckDBErrors]    Script Date: 03-05-2018 13:37:49 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [monitoring].[CheckDBErrors](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[DatabaseName] [nvarchar](75) NULL,
	[ServerName] [nvarchar](128) NULL,
	[CheckDBMessageText] [varchar](7000) NULL,
	[ErrorMessage] [nvarchar](max) NULL,
	[Region] [nvarchar](12) NULL,
	[Logdate] [datetime2](7) NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [monitoring].[CheckDBHistory]    Script Date: 03-05-2018 13:37:49 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [monitoring].[CheckDBHistory](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[DatabaseName] [nvarchar](75) NULL,
	[ServerName] [nvarchar](128) NULL,
	[ShortestRunMinutes] [int] NULL,
	[LongestRunMinutes] [int] NULL,
	[AverageRunMinutes] [decimal](8, 3) NULL,
	[NumberOfRuns] [int] NULL,
	[LatestRun] [datetime2](7) NULL,
	[Region] [nvarchar](12) NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [monitoring].[AutoRestoreMultiFailedDBs] ADD  CONSTRAINT [df_multifailed]  DEFAULT ((0)) FOR [FailedRestoreCount]
GO
ALTER TABLE [monitoring].[AutoRestoreMultiFailedDBs] ADD  DEFAULT ((0)) FOR [BackupRerunNeeded]
GO
ALTER TABLE [monitoring].[CheckDBErrors] ADD  CONSTRAINT [DF_DBCCErrors_Logdate]  DEFAULT (getdate()) FOR [Logdate]
GO
