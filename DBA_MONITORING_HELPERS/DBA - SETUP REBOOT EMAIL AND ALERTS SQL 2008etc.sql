/*

First steps!

Run a find and replace all on {DBAEMAIL}, for example I would use 'dba@seedtreesoft.ca'.

Ditto, the same for {TICKETEMAIL} which is my help desk email, so in my case 'helpdesk@seedtreesoft,ca'.

Finally do the same with {SMTP} and replace that with whatever your SMTP is. D'Oh.

Side note, the very last alert is very optional (just pings if CPU is over a 70% use - you probably have other monitoring in place for that). 

It also tends to fail on some SQL instances - why I do not yet know. 

So feel free to ignore the error, fix it, or comment out the last alert. Your choice!

Cheers!

Martin S. Stoller
20180621

*/

USE [MASTER]
GO
--- Incase you get "Ad hoc update to system catalogs is not supported.", uncomment following and run.
/*
sp_configure 'Allow Updates', 0;
reconfigure with override;
go
-- and just in case:
sp_configure 'Show Advanced Options', 1;
reconfigure with override;
go
*/
/****** CREATE THE DB MAILER PROFILE ********/
exec sp_configure 'show advanced options',1;
RECONFIGURE;
GO
exec sp_configure 'Database Mail XPs', 1; 
RECONFIGURE;
GO
EXECUTE msdb.dbo.sysmail_add_account_sp 
	@account_name = 'DatabaseAdministrators'
	, @description = 'Mail account for DBA e-mail.'
	, @email_address = '{DBAEMAIL}'
	, @replyto_address = '{TICKETEMAIL}'
	, @display_name = 'Database Admins'
	, @mailserver_name = '{SMTP}';
GO
EXECUTE msdb.dbo.sysmail_add_profile_sp @profile_name = 'THE_DBA_MAIL_PROFILE',@description = 'Profile used for DB administrative mail.' ;
GO
EXECUTE msdb.dbo.sysmail_add_profileaccount_sp @profile_name = 'THE_DBA_MAIL_PROFILE',@account_name = 'DatabaseAdministrators',@sequence_number =1 ;
GO
EXECUTE msdb.dbo.sysmail_add_principalprofile_sp @profile_name = 'THE_DBA_MAIL_PROFILE',@principal_name = 'public',@is_default = 1 ;
GO
exec sp_configure 'show advanced options',1;
RECONFIGURE;
exec sp_configure 'scan for startup procs',1;
RECONFIGURE;
GO
/****** CREATE THE EMAIL SP IN MASTER********/
USE [MASTER]
GO
IF OBJECT_ID('dbo.LLFC_REPORT_REBOOT') IS NULL
	EXEC ('CREATE PROCEDURE dbo.LLFC_REPORT_REBOOT AS RETURN 0;');
GO
ALTER PROCEDURE [dbo].[LLFC_REPORT_REBOOT]
AS
BEGIN
	SET NOCOUNT ON;
	-- =============================================
	-- Author:		Martin S. Stoller
	-- Create date: 20100325
	-- Description:	Send and email to DBA each time the SQL service is started.
	-- =============================================
	declare @thebody as nvarchar(255)
	declare @thesubject as nvarchar(255)
	set @thebody = 'Hi there, as '+@@SERVERNAME+' SQL has restarted, please ensure the slave opperations are running again. Thanks!'
	set @thesubject = '[ATTENTION] '+@@SERVERNAME+' SQL RESTARTED!';
	EXEC msdb.dbo.sp_send_dbmail
		@profile_name = 'THE_DBA_MAIL_PROFILE'
		, @recipients = '{DBAEMAIL}'
		, @body = @thebody
		, @subject = @thesubject 
		;
END
/*******************/
GO
EXEC sp_procoption N'[dbo].[LLFC_REPORT_REBOOT]', 'startup', '1';
RECONFIGURE;
GO
SELECT
	[name]
FROM
	sysobjects 
WHERE 
	[type] ='P' and
	OBJECTPROPERTY(id,'ExecIsStartup')=1;
SELECT  
	* 
FROM  
	sys.objects
WHERE   
	object_id = OBJECT_ID(N'LLFC_REPORT_REBOOT')
	AND [type] IN ( N'P', N'PC' );
GO
/***************************** ALERT SETUP *****************/
USE [msdb]
GO
/* USE THIS TO CREAT DROP SCRIPTS FOR ALL ALERTS */ 
/*
	select 
		'EXEC msdb.dbo.sp_delete_alert @name=N'''+name+''''
	from 
		dbo.sysalerts;
*/
/** START AGENT NOTIFICATION SETUP **/
EXEC msdb.dbo.sp_set_sqlagent_properties @email_save_in_sent_folder=1
GO
EXEC master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'UseDatabaseMail', N'REG_DWORD', 1
GO
EXEC master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'DatabaseMailProfile', N'REG_SZ', N'THE_DBA_MAIL_PROFILE'
GO
/** END AGENT NOTIFICATION SETUP **/
/*
	[ @notification_method= ] notification_method
	The method by which the operator is notified. 
	notification_method is tinyint, with no default. 
	notification_method can be one or more of these values combined with an OR logical operator.
	1 = E-mail
	2 = Pager
	4 = net send
	7 = ALL!
*/
declare @note_meth as tinyint = 1; /* EMAIL ONLY  */
/* Var for Alert Name */
declare @alertname nvarchar(255)
/* ADD OPERATORS */
EXEC msdb.dbo.sp_add_operator @name=N'The DBA Team', 
		@enabled=1, 
		@pager_days=0, 
		@email_address=N'{DBAEMAIL}'

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:001 - MISC SYSTEM INFORMATION')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=1,
@enabled=1,
@delay_between_responses=500,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:007 - NOTIFICATION - STATUS INFORMATION')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=7,
@enabled=1,
@delay_between_responses=500,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:008 - NOTIFICATION - USER INTERVENTION REQUIRED')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=8,
@enabled=1,
@delay_between_responses=500,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:009 - USER DEFINED')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=9,
@enabled=1,
@delay_between_responses=500,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:010 - INFORMATION')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=10,
@enabled=1,
@delay_between_responses=500,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:011 - SPECIFIED DB OBJ NOT FOUND')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=11,
@enabled=1,
@delay_between_responses=500,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:012 - UNUSED - YOU SHOULD NOT SEE THIS')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=12,
@enabled=1,
@delay_between_responses=500,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:013 - USER TRANSACTION SYNTAX ERROR')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=13,
@enabled=1,
@delay_between_responses=500,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:014 - INSUFFICIENT PERMISSIONS')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=14,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:016 - MISC USER ERROR')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=16,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:017 - INNSUFIFIENT RESOURCES')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=17,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:018 - NON FATAL INTERNAL ERROR')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=18,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:019 - FATAL ERROR IN RESOURCE')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=19,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:020 - FATAL ERROR IN CURRENT PROCESS')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=20,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:021 - FATAL ERROR IN DATABASE PROCESSES')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=21,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:022 - FATAL ERROR : TABLE INTEGRITY SUSPECT')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=22,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:023 - FATAL ERROR - DATABASE INTEGRITY SUSPECT')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=23,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:024 - FATAL ERROR : HARDWARE')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=24,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Sev:025 - FATAL ERROR')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=0,
@severity=25,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Error:823 - A Windows read or write request has failed.')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=823,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Error:824 - Logical consistency check fails after reading or writing a database page.')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=824,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/*
List all possible ERRORs we can catch.
*/
-- select * from sys.messages;

/*
	http://www.sqlskills.com/blogs/paul/a-little-known-sign-of-impending-doom-error-825/
*/
set @alertname = (select @@SERVERNAME + N' - Error:825 - Your IO subsystem is going wrong and you must do something about it.')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=825,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/*
Error 832: Memory Error, Sql server read data in memory but due to memory problem data is lost/corrupt in memory.
*/
set @alertname = (select @@SERVERNAME + N' - Error:832 - Memory Error - read data is lost/corrupt in memory.')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=832,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/**/
set @alertname = (select @@SERVERNAME + N' - Error:1205 - Deadlock Detected - Naughty Weevil!')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=1205,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

-- message_id	language_id	severity	is_event_logged	text
-- 2571	1033	14	0	User '%.*ls' does not have permission to run DBCC %.*ls.
/* ENABLE LOGGING FOR 2571 */
EXECUTE sp_altermessage 2571, 'WITH_LOG', 'true';  
/* Add Alert*/
set @alertname = (select @@SERVERNAME + N' - Error:2571 - DBCC COMMAND INVOKED WITHOUT PERMISSION!')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=2571,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

-- message_id	language_id	severity	is_event_logged	text
-- 805	1033	10	1	restore pending
set @alertname = (select @@SERVERNAME + N' - Error:805 - DB WITH RESTORE PENDING!')
EXEC msdb.dbo.sp_add_alert @name=@alertname ,
@message_id=805,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'
EXEC msdb.dbo.sp_add_notification @alert_name=@alertname, @operator_name=N'The DBA Team', @notification_method = @note_meth;

/* This one is very optional, that is why last - also it fails on some instances, haven't yet looked into _why_...*/

/* ALERT IF CPU over 70% - wait 60 seconds between alerts */
set @alertname = (select @@SERVERNAME + N' - WARNING - CPU OVER 70%!')
EXEC msdb.dbo.sp_add_alert @name=@alertname,
		@message_id=0, 
		@severity=0, 
		@enabled=1, 
		@delay_between_responses=600, 
		@include_event_description_in=1, 
		@category_name=N'[Uncategorized]', 
		@performance_condition=N'Resource Pool Stats|CPU usage target %|default|>|70', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
GO

print '#done';
GO

/* 

#DONE 

*/




