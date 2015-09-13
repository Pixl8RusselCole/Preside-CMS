component {

	public void function setupApplication(
		  string  id                = CreateUUId()
		, string  name              = arguments.id & ExpandPath( "/" )
		, boolean sessionManagement = true
		, any     sessionTimeout    = CreateTimeSpan( 0, 0, 40, 0 )
	)  {
		this.PRESIDE_APPLICATION_ID = arguments.id;
		this.name                   = arguments.name
		this.sessionManagement      = arguments.sessionManagement;
		this.sessionTimeout         = arguments.sessionTimeout;

		_setupMappings( argumentCollection=arguments );
	}

// APPLICATION LIFECYCLE EVENTS
	public boolean function onApplicationStart() {
		_initEveryEverything();

		return true;
	}

	public boolean function onRequestStart( required string targetPage ) output=true {
		_maintenanceModeCheck();
		_setupInjectedDatasource();
		_readHttpBodyNowBecauseRailoSeemsToBeSporadicallyBlankingItFurtherDownTheRequest();
		_reloadCheck();

		return application.cbBootstrap.onRequestStart( arguments.targetPage );
	}

	public void function onRequestEnd() {
		_invalidateSessionIfNotUsed();
	}

	public boolean function onRequest() output=true {

		// ensure all rquests go through coldbox and requested templates cannot be included directly
		return true;
	}

	public void function onApplicationEnd( required struct appScope ) {
		if ( StructKeyExists( arguments.appScope, "cbBootstrap" ) ) {
			arguments.appScope.cbBootstrap.onApplicationEnd( argumentCollection=arguments );
		}
	}

	public void function onSessionStart() {
		if ( StructKeyExists( arguments, "cbBootstrap" ) ) {
			application.cbBootstrap.onSessionStart();
		}
	}

	public void function onSessionEnd( required struct sessionScope, required struct appScope ) {
		if ( StructKeyExists( arguments.appScope, "cbBootstrap" ) ) {
			arguments.appScope.cbBootstrap.onSessionEnd( argumentCollection=arguments );
		}
	}

	public boolean function onMissingTemplate( required string template ) {
		if ( StructKeyExists( application, "cbBootstrap" ) ) {
			return application.cbBootstrap.onMissingTemplate( argumentCollection=arguments );
		}
	}

	public void function onError(  required struct exception, required string eventName ) output=true {
		if ( _dealWithSqlReloadProtectionErrors( arguments.exception ) ) {
			return;
		}

		if ( _showErrors() ) {
			throw object=arguments.exception;


		} else {
			thread name=CreateUUId() e=arguments.exception {
				new preside.system.services.errors.ErrorLogService().raiseError( attributes.e );
			}

			content reset=true;
			header statuscode=500;

			if ( FileExists( ExpandPath( "/500.htm" ) ) ) {
				Writeoutput( FileRead( ExpandPath( "/500.htm" ) ) );
			} else {
				Writeoutput( FileRead( "/preside/system/html/500.htm" ) );
			}

			return;
		}
	}

// PRIVATE HELPERS
	private void function _setupMappings(
		  string coldboxMapping = "/coldbox"
		, string stickerMapping = "/sticker"
		, string appMapping     = "/app"
		, string assetsMapping  = "/assets"
		, string logsMapping    = "/logs"
		, string coldboxPath    = ExpandPath( "/preside/system/externals/coldbox" )
		, string stickerPath    = ExpandPath( "/preside/system/externals/sticker" )
		, string appPath        = _getApplicationRoot() & "/application"
		, string assetsPath     = _getApplicationRoot() & "/assets"
		, string logsPath       = _getApplicationRoot() & "/logs"
	) {
		this.mappings[ arguments.coldboxMapping ] = arguments.coldboxPath;
		this.mappings[ arguments.stickerMapping ] = arguments.stickerPath;
		this.mappings[ arguments.appMapping     ] = arguments.appPath;
		this.mappings[ arguments.assetsMapping  ] = arguments.assetsPath;
		this.mappings[ arguments.logsMapping    ] = arguments.logsPath;
	}

	private void function _initEveryEverything() {
		setting requesttimeout=1200;

		_fetchInjectedSettings();
		_setupInjectedDatasource();
		_initColdBox();
	}

	private void function _initColdBox() {
		var bootstrap = new preside.system.coldboxModifications.Bootstrap(
			  COLDBOX_CONFIG_FILE   = _discoverConfigPath()
			, COLDBOX_APP_ROOT_PATH = variables.COLDBOX_APP_ROOT_PATH ?: ExpandPath( "/app" )
			, COLDBOX_APP_KEY       = variables.COLDBOX_APP_KEY       ?: ExpandPath( "/app" )
			, COLDBOX_APP_MAPPING   = variables.COLDBOX_APP_MAPPING   ?: "/app"
		);

		bootstrap.loadColdbox();

		application.cbBootstrap = bootstrap;
	}

	private void function _reloadCheck() {
		var reloadRequired = not StructKeyExists( application, "cbBootstrap" ) or application.cbBootStrap.isfwReinit();

		if ( reloadRequired ) {
			_initEveryEverything();
		}
	}

	private void function _fetchInjectedSettings() {
		var settingsManager = new preside.system.services.configuration.InjectedConfigurationManager( app=this, configurationDirectory="/app/config" );
		var config          = settingsManager.getConfig();

		application.injectedConfig = config;
	}

	private void function _setupInjectedDatasource() {
		var config      = application.injectedConfig ?: {};
		var dsnInjected = Len( Trim( config[ "datasource.user" ] ?: "" ) ) && Len( Trim( config[ "datasource.database_name" ] ?: "" ) ) && Len( Trim( config[ "datasource.host" ] ?: "" ) ) && Len( Trim( config[ "datasource.password" ] ?: "" ) );

		if ( dsnInjected ) {
			var dsn        = config[ "datasource.name" ] ?: "preside";
			var useUnicode = config[ "datasource.character_encoding" ] ?: true;

			this.datasources[ dsn ] = {
				  type     : 'MySQL'
				, port     : config[ "datasource.port"          ] ?: 3306
				, host     : config[ "datasource.host"          ]
				, database : config[ "datasource.database_name" ]
				, username : config[ "datasource.user"          ]
				, password : config[ "datasource.password"      ]
				, custom   : {
					  characterEncoding : config[ "datasource.character_encoding" ] ?: "UTF-8"
					, useUnicode        : ( IsBoolean( useUnicode ) && useUnicode )
				  }
			};
		}
	}

	private string function _discoverConfigPath() {
		if ( StructKeyExists( variables, "COLDBOX_CONFIG_FILE" ) ) {
			return variables.COLDBOX_CONFIG_FILE;
		}

		if ( FileExists( "/app/config/LocalConfig.cfc" ) ) {
			return "app.config.LocalConfig";
		}

		if ( FileExists( "/app/config/Config.cfc" ) ) {
			return "app.config.Config";
		}

		return "preside.system.config.Config";
	}

	private void function _readHttpBodyNowBecauseRailoSeemsToBeSporadicallyBlankingItFurtherDownTheRequest() {
		request.http = { body = ToString( GetHttpRequestData().content ) };
	}

	private boolean function _showErrors() {
		var coldboxController = _getColdboxController();
		var injectedExists    = IsBoolean( application.injectedConfig.showErrors ?: "" );
		var nonColdboxDefault = injectedExists && application.injectedConfig.showErrors;

		if ( !injectedExists ) {
			var localEnvRegexes = this.LOCAL_ENVIRONMENT_REGEX ?: "^local\.,\.local$,^localhost(:[0-9]+)?$,^127.0.0.1(:[0-9]+)?$";
			var host            = cgi.http_host;
			for( var regex in ListToArray( localEnvRegexes ) ) {
				if ( ReFindNoCase( regex, host ) ) {
					nonColdboxDefault = true;
					break;
				}
			}
		}

		return IsNull( coldboxController ) ? nonColdboxDefault : coldboxController.getSetting( name="showErrors", defaultValue=nonColdboxDefault );
	}

	private any function _getColdboxController() {
		if ( StructKeyExists( application, "cbBootstrap" ) && IsDefined( 'application.cbBootstrap.getController' ) ) {
			return application.cbBootstrap.getController();
		}

		return;
	}

	private boolean function _dealWithSqlReloadProtectionErrors( required struct exception ) output=true {
		var exceptionType = ( arguments.exception.type ?: "" );

		if ( exceptionType == "presidecms.auto.schema.sync.disabled" ) {
			thread name=CreateUUId() e=arguments.exception {
				new preside.system.services.errors.ErrorLogService().raiseError( attributes.e );
			}

			header statuscode=500;content reset=true;
			include template="/preside/system/views/errors/sqlRebuild.cfm";
			return true;
		}

		return false;
	}

	private void function _maintenanceModeCheck() {
		new preside.system.services.maintenanceMode.MaintenanceModeService().showMaintenancePageIfActive();
	}

	private void function _invalidateSessionIfNotUsed() {
		var sessionIsUsed        = false;
		var ignoreKeys           = [ "cfid", "timecreated", "sessionid", "urltoken", "lastvisit", "cftoken" ];
		var keysToBeEmptyStructs = [ "cbStorage", "cbox_flash_scope" ];

		for( var key in session ) {
			if ( ignoreKeys.findNoCase( key ) ) {
				continue;
			}

			if ( keysToBeEmptyStructs.findNoCase( key ) && IsStruct( session[ key ] ) && session[ key ].isEmpty() ) {
				continue;
			}

			sessionIsUsed = true;
			break;
		}

		if ( !sessionIsUsed ) {
			session.setMaxInactiveInterval(  javaCast( "long", 1 ) );
			getPageContext().setHeader( "Set-Cookie", "" );
		}
	}

	private string function _getApplicationRoot() {
		var trace      = CallStackGet();
		var appCfcPath = trace[ trace.len() ].template;
		var dir        = GetDirectoryFromPath( appCfcPath );

		return ReReplace( dir, "/$", "" );
	}
}