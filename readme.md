1. Download [Boxstarter](http://www.boxstarter.org/)
	* unzip to temporary folder
	* run setup.bat
	
2. Open boxstarter shell (shortcut on desktop)
	* run the following command
	````powershell
	Install-Package -packageName https://
	````

3. Make sure that all windows features required are installed
	* Internet Information Services
		* Web Management Tools
			* IIS Management Console
			* IIS Management Scripts and Tools
		* World Wide Web Services
			* Application Development Features
				* .NET Extensibility 4.6
				* Application Initialization
				* ASP.NET 4.6
				* ISAPI Extensions
				* ISAPI Filters
			* Common HTTP Features
				* All but WebDAV Publishing
			* Health and Diagnostics
				* All
			* Performance Features
				* All
			* Security
				* Basic Authentication
				* Request Filtering
	