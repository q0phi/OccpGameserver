module OCCPGameServer

    require 'sinatra/base'
    require'json'

    class WebListener < Sinatra::Base

        VERSION='0.2.0'
        #Challenge Run States
        WAIT = 1
        READY = 2
        RUN = 3
        STOP = 4
        QUIT = 5

        @@game_states = {
            WAIT => 'Paused',
            READY => 'Ready',
            RUN => 'Running',
            STOP => 'Stopped',
            QUIT => 'Exiting'
        }
        @@game_state_verbs = {
            WAIT => 'PAUSE',
            READY => 'READY',
            RUN => 'RUN',
            STOP => 'STOP',
            QUIT => 'QUIT'
        }

	before do
		headers "Access-Control-Allow-Origin" => "*"
	end
=begin
    @api {get} / Request System Information
    @apiVersion 0.1.0
    @apiName Root
    @apiGroup System

    @apiSuccess {String} application Name of the application
    @apiSuccess {String} version Version of the application

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "application" : "OCCP GameServer",
            "version" : "1.0.0"
        }

=end
        get '/', :provides => :json do
            info = {:Application => "OCCP GameServer", :Version => OCCPGameServer::VERSION}
            JSON.generate(info)
        end
        get '/', :provides => :html do
            "<html><head><title><GameServer API Server</title></head><body><h1>GameServer API Server v#{VERSION} Started</h1></body></html>"
        end

=begin
    @api {get} /scenario/ Request Scenario Information
    @apiVersion 0.1.0
    @apiName GetScenario
    @apiGroup Scenario

    @apiSuccess {String} name Name of the scenario
    @apiSuccess {String} id ID of the scenario
    @apiSuccess {String} type Type of the scenario
    @apiSuccess {Number} length Length of the scenario in seconds
    @apiSuccess {String} description Short description of the activity of the scenario

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "name" : "Red Team v. Blue Team",
            "id" : "1",
            "type" : "Network Defense",
            "length" : "300",
            "description" : "A two sentence description of the scenario."
        }

=end
=begin
    @api {get} /scenario/ Request Scenario Information
    @apiVersion 0.2.0
    @apiName GetScenario
    @apiGroup Scenario

    @apiSuccess {String} name Name of the scenario
    @apiSuccess {String} id ID of the scenario
    @apiSuccess {String} uid A unique identifier for each run of the scenario (changes each game server restart)
    @apiSuccess {String} type Type of the scenario
    @apiSuccess {Number} length Length of the scenario in seconds
    @apiSuccess {String} description Short description of the activity of the scenario

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "name" : "Red Team v. Blue Team",
            "id" : "1",
            "uid": "d8febc5-ad4fr5-3ff4f-434cec"
            "type" : "Network Defense",
            "length" : "300",
            "description" : "A two sentence description of the scenario."
        }

=end
        get '/scenario/' do

            info = {    :name => $appCore.scenarioname,
                        :id => $appCore.gameid,
                        :type => $appCore.type,
                        :length => $appCore.gameclock.gamelength,
                        :description => $appCore.description,
                        :uid => $appCore.scenariouid
            }
            JSON.generate(info)
        end

=begin
    @api {get} /gameclock/ Read the game clock
    @apiVersion 0.1.0
    @apiName GetGameClock
    @apiGroup GameClock
    @apiDescription Read the available information about the game clock. The <code>length</code> and <code>gametime</code>
    fields are reported in seconds.

    @apiSuccess {Number} length Length of the scenario in seconds
    @apiSuccess {Number} gametime Current value of the game clock in seconds
    @apiSuccess {String} state The current state of the game clock

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "length" : 300,
            "gametime" : 15,
            "state" : "RUN"
        }

=end
        get '/gameclock/' do
            info = {
                    :length => $appCore.gameclock.gamelength,
                    :gametime => $appCore.gameclock.gametime,
                    :state => @@game_states[$appCore.STATE]
            }
            JSON.generate(info)
        end

=begin
    @api {put} /gameclock/ Change the game clock
    @apiVersion 0.1.0
    @apiName SetGameClock
    @apiGroup GameClock

    @apiParam {Number} length Length of the scenario in seconds
    @apiParam {Number} state The current state of the game clock

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "length" : 300,
            "state" : 'Running'
        }
    @apiError (Error 400) invalidInputError The data for the request was not correct JSON
    @apiErrorExample Error-Response (example):
        HTTP/1.1 400 BAD REQUEST
        {
            "error" : "invalidInputError"
        }
    @apiError (Error 422) invalidValuesError The data for the request was not valid for the entity
    @apiErrorExample Error-Response (example):
        HTTP/1.1 422 UNPROCESSABLE ENTITY
        {
            "error" : "invalidValuesError"
        }

=end
        put '/gameclock/' do
            request.body.rewind

            begin
                data = JSON.parse request.body.read
                info = {}
                if data["state"] and @@game_state_verbs[Integer(data["state"])]
                    info[:state] = Integer(data["state"])
                end
                if data["length"] and Integer(data["length"])
                    info[:length] = Integer(data["length"])
                end

                if info[:state] #update the game state
                    $appCore.INBOX << GMessage.new({:fromid=>'WebClient',:signal=>'COMMAND',:msg=>{:command => 'STATE', :state=>info[:state]}})
                    info[:state] = @@game_states[info[:state]]
                end
                if info[:length] #update the game state
                    $appCore.INBOX << GMessage.new({:fromid=>'WebClient',:signal=>'COMMAND',:msg=>{:command => :LENGTH, :length=>info[:length]}})
                end

                res = JSON.generate info
            rescue ArgumentError=>e
                res = [422, {:error=>"invalidValuesError"}.to_json]
            rescue JSON::ParserError=>e
                res = [400, {:error=>"invalidInputError"}.to_json]
            end
            res
        end

=begin
    @api {get} /gameclock/states/ Read the game states
    @apiVersion 0.1.0
    @apiName GetGameStateVerbs
    @apiGroup GameClock

    @apiSuccess {String} stateverb Name of the verb used to set a state
    @apiSuccess {Number} statevalue Value to use in state

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        [
            {
                "stateverb": "PAUSE",
                "statevalue": 1
            },
            {
                "stateverb": "READY",
                "statevalue": 2
            },
            . . .
        ]
=end
        get '/gameclock/states/' do
            res = @@game_state_verbs.inject([]){|memo,(k,v)| memo << {:stateverb=>v,:statevalue=>k}; memo }
            JSON.generate(res)
        end

=begin
    @api {get} /teams/ Read all teams
    @apiVersion 0.1.0
    @apiName GetTeams
    @apiGroup Teams

    @apiSuccess {String} name Name of the team
    @apiSuccess {String} id Id of the team

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        [ {
            "name" : "Blue Team",
            "id" : "1235-1235-1235"
          },
          ...
        ]

=end
        get '/teams/' do
            teams = []
            $appCore.teams.each do |team|
                teams << {:name=>team.teamname,:id=>team.teamid}
            end
            JSON.generate(teams)
        end

=begin
    @api {get} /teams/<teamid>/ Read team data
    @apiVersion 0.1.0
    @apiName GetTeam
    @apiGroup Teams

    @apiSuccess {String} name Name of the team
    @apiSuccess {String} id ID of the team
    @apiSuccess {String} rate Event execution rate
    @apiSuccess {String} state The running state of the team

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "name" : "Blue Team",
            "id" : "1235-1235-1235",
            "rate" : "1.0",
            "state" : "WAIT"
        }
    @apiError (Error 4xx) TeamNotFound The team for the given id was not found
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "TeamNotFound"
        }
=end
        get '/teams/:id/' do
            teaminfo = nil
            $appCore.teams.each do |team|
                if team.teamid == params[:id]
                    teaminfo = { :name=>team.teamname,
                        :id=>team.teamid,
                        :rate=>team.speedfactor,
                        :state=>team.STATE }
                end
            end
            if teaminfo.nil?
                res = [404, {:error=>"TeamNotFound"}.to_json]
            else
                res = JSON.generate(teaminfo)
            end
            res
        end
=begin
    @api {get} /teams/<teamid>/events/ Read team events
    @apiVersion 0.2.0
    @apiName GetTeamEvents
    @apiGroup Teams

    @apiParam {Number} [start_index=0] Optional Starting Index Entry
    @apiParam {Number} [max_results=20] Optional Maximum Results Per Page

    @apiSuccess {Number} numberOfResults Number of results found
    @apiSuccess {Number} startIndex Starting index of this page
    @apiSuccess {Number} resultsPerPage Number of results per page
    @apiSuccess {Object[]} events Array of events belonging to this team
    @apiSuccess {String} events.uuid Unique ID of event isntance
    @apiSuccess {String} events.guid Registry ID of event type
    @apiSuccess {String} events.name Name of the event
    @apiSuccess {String} events.handler Handler class for the event
    @apiSuccess {String} events.starttime '''GameTime''' start time for the event
    @apiSuccess {String} events.endtime '''GameTime''' end time for the event
    @apiSuccess {Number} events.frequency The number of seconds to elapse between successive events
    @apiSuccess {Number} events.drift The number of seconds (+/-)to drift from the expected execution time
    @apiSuccess {String} events.ipaddresspool IP address assignment pool
    @apiSuccess {Boolean} deleted Deletion status of the event
    @apiSuccess {Boolean} completed Completion status of the event
    @apiSuccess {Object[]} events.scores Score items associated with this event
    @apiSuccess {String} events.scores.scoregroup Score group label for this score
    @apiSuccess {String} events.scores.points Number of points to assign for this score
    @apiSuccess {Boolean} events.scores.onsuccess Whether to assign points when event succeeds or fails


    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "numberOfResults": 250,
            "startIndex": 0,
            "resultsPerPage": 20,
            "events": [
                {
                    "uuid" : "123456-1234-123456",
                    "guid" : "q-w-e",
                    "name" : "ping",
                    "handler" : "exec-handler-1",
                    "starttime" : "00:00:00",
                    "endtime" : "00:00:00",
                    "frequency" : "2",
                    "drift" : "0",
                    "ipaddresspool" : "pub_1",
                    "deleted" : false,
                    "completed": false,
                    "scores" : [
                        { "score-group" : "redteam", "points" : "-13", "onsuccess" : "false" },
                        { "score-group" : "blueteam", "points" : "13", "onsuccess" : "true" }
                        ]
                },
                . . .
                ]
        }

    @apiError (Error 4xx) TeamNotFound The team for the given id was not found
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "TeamNotFound"
        }
=end
        get '/teams/:id/events/' do
            teaminfo = nil
            events = []
            $appCore.teams.each do |team|
                if String(team.teamid) == params[:id]
                    teaminfo = true
                    #Iterate through each list of events of the team
                    team.singletonList.each do |event|
                        events << event.wshash
                    end
                    team.periodicList.each do |event|
                        events << event.wshash
                    end
                end
            end
            if teaminfo.nil?
                res = [404, {:error=>"TeamNotFound"}.to_json]
            else
                res = JSON.generate(events)
            end
            res
        end

=begin
    @api {get} /teams/<teamid>/events/<eventuid> Read team event
    @apiVersion 0.2.0
    @apiName GetTeamEvent
    @apiGroup Teams

    @apiSuccess {String} uuid Unique ID of event isntance
    @apiSuccess {String} guid Registry ID of event type
    @apiSuccess {String} name Name of the event
    @apiSuccess {String} handler Handler class for the event
    @apiSuccess {String} starttime '''GameTime''' start time for the event
    @apiSuccess {String} endtime '''GameTime''' end time for the event
    @apiSuccess {Number} frequency The number of seconds to elapse between successive events
    @apiSuccess {Number} drift The number of seconds (+/-)to drift from the expected execution time
    @apiSuccess {String} ipaddresspool IP address assignment pool
    @apiSuccess {Boolean} deleted Deletion status of the event
    @apiSuccess {Boolean} completed Completion status of the event
    @apiSuccess {Object[]} scores Score items associated with this event
    @apiSuccess {String} scores.scoregroup Score group label for this score
    @apiSuccess {String} scores.points Number of points to assign for this score
    @apiSuccess {Boolean} scores.onsuccess Whether to assign points when event succeeds or fails


    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "uuid" : "123456-1234-123456",
            "guid" : "q-w-e",
            "name" : "ping",
            "handler" : "exec-handler-1",
            "starttime" : "00:00:00",
            "endtime" : "00:00:00",
            "frequency" : "2",
            "drift" : "0",
            "ipaddresspool" : "pub_1",
            "deleted" : false,
            "completed": false,
            "scores" : [
                { "score-group" : "redteam", "points" : "-13", "onsuccess" : "false" },
                { "score-group" : "blueteam", "points" : "13", "onsuccess" : "true" }
                ]
        }

    @apiError (Error 4xx) TeamNotFound The team for the given id was not found
    @apiError (Error 4xx) EventNotFound The event for the given id was not found
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "TeamNotFound"|"EventNotFound"
        }
=end
        get '/teams/:id/events/:eventuid/' do
            teaminfo = nil
            events = []
            $appCore.teams.each do |team|
                if String(team.teamid) == params[:id]
                    teaminfo = true
                    #Iterate through each list of events of the team
                    team.singletonList.each do |event|
                        if event.eventuid == params[:eventuid]
                            events = event.wshash
                            break
                        end
                    end
                    if events.empty?
                        team.periodicList.each do |event|
                            if event.eventuid == params[:eventuid]
                                events = event.wshash
                                break
                            end
                        end
                    end
                    break
                end
            end
            if teaminfo.nil?
                res = [404, {:error=>"TeamNotFound"}.to_json]
            elsif events.empty?
                res = [404, {:error=>"EventNotFound"}.to_json]
            else
                res = JSON.generate(events)
            end
            res
        end

=begin
    @api {get} /scores/ Read all available score names
    @apiVersion 0.1.0
    @apiName GetScores
    @apiGroup Scores

    @apiDescription Provides an array of all of the score names that the gameserver knows about.

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        [
            "service-level",
            "wage-level",
            "empl-level"
        ]

    @apiError (Error 4xx) ScoresNotFound There are no score names defined in the system.
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "ScoresNotFound"
        }
=end
=begin
    @api {get} /scores/ Read all available scores
    @apiVersion 0.2.0
    @apiName GetScores
    @apiGroup Scores

    @apiDescription Provides an array of all of the scores that the gameserver knows about.

    @apiSuccess {String} name Name of the score
    @apiSuccess {String} value Value of the score
    @apiSuccess {String} longname Pretty Print version of the score name
    @apiSuccess {String} description An optional description of what the score ranks

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        [
            {
                name: "service-level",
                value: "0.0",
                longname: "Service Level"
                description: "This score shows how long the service stayed alive."
            },
              ...
        ]

    @apiError (Error 4xx) ScoresNotFound There are no score names defined in the system.
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "ScoresNotFound"
        }
=end
        get '/scores/' do
            score_names = $appCore.scoreKeeper.get_scores
            output = []

            score_names.each do |scorename|
                value = $appCore.scoreKeeper.get_score(scorename.name)
                output.push( { :name => scorename.name, :longname => scorename.lname, :value => value, :description => scorename.descr })
            end


            if output.nil? || output.empty?
                res = [404, {:error=>"ScoresNotFound"}.to_json]
            end

            res = JSON.generate(output)
            res
        end

=begin
    @api {get} /scores/stats/ Read score statistics
    @apiVersion 0.2.0
    @apiName GetScoreStats
    @apiGroup Scores

    @apiDescription Provides an array of object that each containa a score name and an array of score data .

    @apiSuccess {String} name Name of the score
    @apiSuccess {String} value Value of the score

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        [
            {
                name: "service-level",
                value: [ 0, 2, 4, 6, 8]
            },
              ...
        ]

    @apiError (Error 4xx) ScoreStatisticsNotFound There are no score statistics available.
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "ScoreStatisticsNotFound"
        }
=end
        get '/scores/stats/' do

            score_names = $appCore.scoreKeeper.get_scores
            output = []

            score_names.each do |scorename|
                value = $appCore.scoreKeeper.get_score_stats(scorename.name)
                output.push( { :name => scorename.name, :value => value } )
            end


            if output.nil? || output.empty?
                res = [404, {:error=>"ScoreStatisticsNotFound"}.to_json]
            end

            res = JSON.generate(output)
            res
        end

=begin
    @api {put} /scores/stats/ Read score statistics
    @apiVersion 0.2.0
    @apiName GetScoreStats
    @apiGroup Scores

    @apiDescription Provides an array of object that each containa a score name and an array of score data .

    @apiSuccess {String} name Name of the score
    @apiSuccess {String} value Value of the score

    @apiParam {Number} [gametime] Optional End time of the range to select. Default current gametime.
    @apiParam {Number} [length] Optional Number of seconds in the range. Counts from [gametime] backwards.

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        [
            {
                name: "service-level",
                value: [ 0, 2, 4, 6, 8]
            },
              ...
        ]

    @apiError (Error 4xx) ScoreStatisticsNotFound There are no score statistics available.
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "ScoreStatisticsNotFound"
        }
=end

        put '/scores/stats/' do

            #Grab any provided parameters set defaults otherwise
            request.body.rewind

            info = {}

            begin
                bodydata = JSON.parse request.body.read
                if bodydata["gametime"] and Integer(bodydata["gametime"])
                    info[:gametime] = Integer(bodydata["gametime"])
                end
                if bodydata["length"] and Integer(bodydata["length"])
                    info[:length] = Integer(bodydata["length"])
                end
            rescue ArgumentError=>e
                res = [422, {:error=>"invalidValuesError"}.to_json]
            rescue JSON::ParserError=>e
                res = [400, {:error=>"invalidInputError"}.to_json]
            end
            if res
                return res
            end

            score_names = $appCore.scoreKeeper.get_scores
            output = []

            score_names.each do |scorename|
                value = $appCore.scoreKeeper.get_score_stats(scorename.name, info)
                output.push( { :name => scorename.name, :value => value } )
            end


            if output.nil? || output.empty?
                res = [404, {:error=>"ScoreStatisticsNotFound"}.to_json]
            end

            res = JSON.generate(output)
            res
        end

=begin
    @api {get} /scores/<scorename>/ Read a specified score name's information
    @apiVersion 0.1.0
    @apiName GetScoreInformation
    @apiGroup Scores

    @apiDescription Provides the current value of a defined score name.

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            name: "service-level",
            value: "0.0"
        }

    @apiError (Error 4xx) ScoreNameNotFound There are no score names defined with the supplied name.
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "ScoreNameNotFound"
        }
=end

        get '/scores/:name/' do
               output = {}
            $appCore.scoreKeeper.get_names.each do |scorename|
                if scorename == params[:name]
                    value = $appCore.scoreKeeper.get_score(scorename)
                    output = { :name => scorename, :value => value }
                end
            end
            if output.empty?
                res = [404, {:error=>"ScoreNameNotFound"}.to_json]
            else
                res = JSON.generate(output)
            end
            res
        end



=begin
    @api {get} /logevents/ Read all log events from the database
    @apiVersion 0.1.0
    @apiName GetEventLogs
    @apiGroup Log

    @apiDescription Provides the current entries of log database. Not Currently Paginated.

    @apiSuccess {String} rowid Unique ID of log entry
    @apiSuccess {Number} time Time that the log entry was created in UNIX Epoch seconds
    @apiSuccess {Number} gametimestart Time on the gameclock when the event was initiated in seconds
    @apiSuccess {Number} gametimeend  Time on the gameclock when the event was completed in seconds
    @apiSuccess {String} handler Handler class for the event
    @apiSuccess {String} eventname Name of the event
    @apiSuccess {String} eventid Registry ID of event type
    @apiSuccess {String} eventuid Unique ID of event isntance
    @apiSuccess {String} custom Custom string supplied by the execution handler
    @apiSuccess {String} status Event completion status as defined by the execution handler

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        [{
            "rowid":12,
            "time":1466545618,
            "gametimestart":12.141730549,
            "gametimeend":15.150756999000002,
            "handler":"NagiosPluginHandler",
            "eventname":"check homepage noise",
            "eventid":"",
            "eventuid":"1d9413a4-4f11-47a9-9261-26ebaa8391c1",
            "custom":"/usr/lib/nagios/plugins/check_http -I 185.110.107.101",
            "status":"FAIL"
        }, ...
        ]

    @apiError (Error 4xx) NoLogEventsFound There are no log events stored in the database.
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "NoLogEventsFound"
        }
=end
	get '/logevents/' do

        output = []
        res = $db.query('SELECT rowid,* FROM EVENTS')
        if res
            cols = res.columns
            res.each do |row|
                output << Hash[cols.zip(row)]
            end
            res.close
        end

        if output.empty?
            res = [404, {:error=>"NoLogEventsFound"}.to_json]
        else
            res = JSON.generate(output)
        end

        res
	end

=begin
    @api {get} /logevents/since/<rowid>/ Read all log events from the database that occur after the provided entry id.
    @apiVersion 0.1.0
    @apiName GetEventLogsSince
    @apiGroup Log

    @apiSuccess {String} rowid Unique ID of log entry
    @apiSuccess {Number} time Time that the log entry was created in UNIX Epoch seconds
    @apiSuccess {Number} gametimestart Time on the gameclock when the event was initiated in seconds
    @apiSuccess {Number} gametimeend  Time on the gameclock when the event was completed in seconds
    @apiSuccess {String} handler Handler class for the event
    @apiSuccess {String} eventname Name of the event
    @apiSuccess {String} eventid Registry ID of event type
    @apiSuccess {String} eventuid Unique ID of event isntance
    @apiSuccess {String} custom Custom string supplied by the execution handler
    @apiSuccess {String} status Event completion status as defined by the execution handler

    @apiDescription Provides the current entries of log database that occur after the supplied entry id. Not Currently Paginated.

    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        [{
            "rowid":12,
            "time":1466545618,
            "gametimestart":12.141730549,
            "gametimeend":15.150756999000002,
            "handler":"NagiosPluginHandler",
            "eventname":"check homepage noise",
            "eventid":"",
            "eventuid":"1d9413a4-4f11-47a9-9261-26ebaa8391c1",
            "custom":"/usr/lib/nagios/plugins/check_http -I 185.110.107.101",
            "status":"FAIL"
        }, ...
        ]

    @apiError (Error 4xx) NoLogEventsFound There are no log events newer than the supplied log entry id.
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "NoLogEventsFound"
        }
=end
    get '/logevents/since/:rowid/' do

        output = []
        res = $db.query('SELECT rowid,* FROM EVENTS WHERE rowid > ?', params[:rowid])
        if res
            cols = res.columns

            res.each do |row|
                output << Hash[cols.zip(row)]
            end
            res.close
        end

        if output.empty?
            res = [404, {:error=>"NoLogEventsFound"}.to_json]
        else
            res = JSON.generate(output)
        end

        res
	end

=begin
    @api {get} /events/ Read all events
    @apiVersion 0.2.0
    @apiName GetEvents
    @apiGroup Events

    @apiParam {Number} [start_index=0] Optional Starting Index Entry
    @apiParam {Number} [max_results=20] Optional Maximum Results Per Page

    @apiSuccess {Number} numberOfResults Number of results found
    @apiSuccess {Number} startIndex Starting index of this page
    @apiSuccess {Number} resultsPerPage Number of results per page
    @apiSuccess {Object[]} events Array of events belonging to this team
    @apiSuccess {String} events.uuid Unique ID of event isntance
    @apiSuccess {String} events.guid Registry ID of event type
    @apiSuccess {String} events.teamid Unique ID of the parent team
    @apiSuccess {String} events.name Name of the event
    @apiSuccess {String} events.handler Handler class for the event
    @apiSuccess {String} events.starttime '''GameTime''' start time for the event
    @apiSuccess {String} events.endtime '''GameTime''' end time for the event
    @apiSuccess {Number} events.frequency The number of seconds to elapse between successive events
    @apiSuccess {Number} events.drift The number of seconds (+/-)to drift from the expected execution time
    @apiSuccess {String} events.ipaddresspool IP address assignment pool
    @apiSuccess {Boolean} deleted Deletion status of the event
    @apiSuccess {Boolean} completed Completion status of the event
    @apiSuccess {Object[]} events.scores Score items associated with this event
    @apiSuccess {String} events.scores.scoregroup Score group label for this score
    @apiSuccess {String} events.scores.points Number of points to assign for this score
    @apiSuccess {Boolean} events.scores.onsuccess Whether to assign points when event succeeds or fails


    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
        {
            "numberOfResults": 250,
            "startIndex": 0,
            "resultsPerPage": 20,
            "events": [
                {
                    "uuid" : "123456-1234-123456",
                    "guid" : "q-w-e",
                    "teamid" : "123456-1234-123456",
                    "name" : "ping",
                    "handler" : "exec-handler-1",
                    "starttime" : "00:00:00",
                    "endtime" : "00:00:00",
                    "frequency" : "2",
                    "drift" : "0",
                    "ipaddresspool" : "pub_1",
                    "deleted" : false,
                    "completed": false,
                    "scores" : [
                        { "score-group" : "redteam", "points" : "-13", "onsuccess" : "false" },
                        { "score-group" : "blueteam", "points" : "13", "onsuccess" : "true" }
                        ]
                },
                . . .
                ]
        }

    @apiError (Error 4xx) EventsNotFound No events for this scenario found
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "EventsNotFound"
        }
=end
        get '/events/' do
            teaminfo = nil
            events = []
            $appCore.teams.each do |team|
                    #Iterate through each list of events of the team
                    team.singletonList.each do |event|
                        eventhash = event.wshash
                        eventhash[:teamid] = team.teamid
                        events << eventhash
                    end
                    team.periodicList.each do |event|
                        eventhash = event.wshash
                        eventhash[:teamid] = team.teamid
                        events << eventhash
                    end
            end
            if events.empty?
                res = [404, {:error=>"EventsNotFound"}.to_json]
            else
                res = JSON.generate(events)
            end
            res
        end

=begin
    @api {get} /events/<eventid>/ Read event by uuid
    @apiVersion 0.2.0
    @apiName GetEvent
    @apiGroup Events

    @apiSuccess {String} uuid Unique ID of event isntance
    @apiSuccess {String} guid Registry ID of event type
    @apiSuccess {String} teamid Unique ID of the parent team
    @apiSuccess {String} name Name of the event
    @apiSuccess {String} handler Handler class for the event
    @apiSuccess {String} starttime '''GameTime''' start time for the event
    @apiSuccess {String} endtime '''GameTime''' end time for the event
    @apiSuccess {Number} frequency The number of seconds to elapse between successive events
    @apiSuccess {Number} drift The number of seconds (+/-)to drift from the expected execution time
    @apiSuccess {String} ipaddresspool IP address assignment pool
    @apiSuccess {Boolean} deleted Deletion status of the event
    @apiSuccess {Boolean} completed Completion status of the event
    @apiSuccess {Object[]} scores Score items associated with this event
    @apiSuccess {String} scores.scoregroup Score group label for this score
    @apiSuccess {String} scores.points Number of points to assign for this score
    @apiSuccess {Boolean} scores.onsuccess Whether to assign points when event succeeds or fails


    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
       {
            "uuid" : "123456-1234-123456",
            "guid" : "q-w-e",
            "teamid" : "123456-1234-123456",
            "name" : "ping",
            "handler" : "exec-handler-1",
            "starttime" : "00:00:00",
            "endtime" : "00:00:00",
            "frequency" : "2",
            "drift" : "0",
            "ipaddresspool" : "pub_1",
            "deleted" : false,
            "completed": false,
            "scores" : [
                { "score-group" : "redteam", "points" : "-13", "onsuccess" : "false" },
                { "score-group" : "blueteam", "points" : "13", "onsuccess" : "true" }
                ]
        }

    @apiError (Error 4xx) EventNotFound No event for this uuid
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "EventNotFound"
        }
=end
        get '/events/:eventuid/' do
            teaminfo = nil
            eventRecord = nil
            $appCore.teams.each do |team|
                #Iterate through each list of events of the team
                team.singletonList.each do |event|
                    if event.eventuid == params[:eventuid]
                        eventhash = event.wshash
                        eventhash[:teamid] = team.teamid
                        eventRecord = eventhash
                        break
                    end
                end
                if eventRecord.nil?
                    team.periodicList.each do |event|
                        if event.eventuid == params[:eventuid]
                            eventhash = event.wshash
                            eventhash[:teamid] = team.teamid
                            eventRecord = eventhash
                            break
                        end
                    end
                end
            end
            if eventRecord.nil?
                res = [404, {:error=>"EventNotFound"}.to_json]
            else
                res = JSON.generate(eventRecord)
            end
            res
        end

=begin
    @api {delete} /events/<eventid>/ Delete event by uuid
    @apiVersion 0.2.0
    @apiName DeleteEvent
    @apiGroup Events

    @apiSuccess {String} uuid Unique ID of event isntance
    @apiSuccess {String} guid Registry ID of event type
    @apiSuccess {String} teamid Unique ID of the parent team
    @apiSuccess {String} name Name of the event
    @apiSuccess {String} handler Handler class for the event
    @apiSuccess {String} starttime '''GameTime''' start time for the event
    @apiSuccess {String} endtime '''GameTime''' end time for the event
    @apiSuccess {Number} frequency The number of seconds to elapse between successive events
    @apiSuccess {Number} drift The number of seconds (+/-)to drift from the expected execution time
    @apiSuccess {String} ipaddresspool IP address assignment pool
    @apiSuccess {Boolean} deleted Deletion status of the event
    @apiSuccess {Boolean} completed Completion status of the event
    @apiSuccess {Object[]} scores Score items associated with this event
    @apiSuccess {String} scores.scoregroup Score group label for this score
    @apiSuccess {String} scores.points Number of points to assign for this score
    @apiSuccess {Boolean} scores.onsuccess Whether to assign points when event succeeds or fails


    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
       {
            "uuid" : "123456-1234-123456",
            "guid" : "q-w-e",
            "teamid" : "123456-1234-123456",
            "name" : "ping",
            "handler" : "exec-handler-1",
            "starttime" : "00:00:00",
            "endtime" : "00:00:00",
            "frequency" : "2",
            "drift" : "0",
            "ipaddresspool" : "pub_1",
            "deleted" : true,
            "completed": false,
            "scores" : [
                { "score-group" : "redteam", "points" : "-13", "onsuccess" : "false" },
                { "score-group" : "blueteam", "points" : "13", "onsuccess" : "true" }
                ]
        }

    @apiError (Error 4xx) EventNotFound No event for this uuid
    @apiError (Error 5xx) EventNotDeleted Could not delete event
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "EventNotFound"|"EventNotDeleted"
        }
=end
        delete '/events/:eventuid/' do
            teaminfo = nil
            eventRecord = nil
            $appCore.teams.each do |team|
                #Iterate through each list of events of the team
                team.singletonList.each do |event|
                    if event.eventuid == params[:eventuid]
                        event.setdeleted()
                        eventhash = event.wshash
                        eventhash[:teamid] = team.teamid
                        eventRecord = eventhash
                        break
                    end
                end
                if eventRecord.nil?
                    team.periodicList.each do |event|
                        if event.eventuid == params[:eventuid]
                            event.setdeleted()
                            eventhash = event.wshash
                            eventhash[:teamid] = team.teamid
                            eventRecord = eventhash
                            break
                        end
                    end
                end
            end
            if eventRecord.nil?
                res = [404, {:error=>"EventNotFound"}.to_json]
            else
                res = JSON.generate(eventRecord)
                $appCore.INBOX << GMessage.new({:fromid=>'WebClient',:signal=>'LOG',:msg=>"Event Marked Deleted: #{eventRecord[:uuid]}"})
            end

            res
        end

=begin
    @api {put} /events/<eventid>/ Update event by uuid
    @apiVersion 0.2.0
    @apiName PutEvent
    @apiGroup Events

    @apiParam {String} teamid Unique ID of the parent team
    @apiParam {String} name Name of the event
    @apiParam {String} handler Handler class for the event
    @apiParam {String} starttime '''GameTime''' start time for the event
    @apiParam {String} endtime '''GameTime''' end time for the event
    @apiParam {Number} frequency The number of seconds to elapse between successive events
    @apiParam {Number} drift The number of seconds (+/-)to drift from the expected execution time
    @apiParam {String} ipaddresspool IP address assignment pool
    @apiParam {Boolean} deleted Deletion status of the event
    @apiParam {Object[]} scores Score items associated with this event
    @apiParam {String} scores.scoregroup Score group label for this score
    @apiParam {String} scores.points Number of points to assign for this score
    @apiParam {Boolean} scores.onsuccess Whether to assign points when event succeeds or fails


    @apiSuccessExample Success-Response (example):
        HTTP/1.1 200 OK
       {
            "teamid" : "123456-1234-123456",
            "name" : "ping",
            "handler" : "exec-handler-1",
            "starttime" : "00:00:00",
            "endtime" : "00:00:00",
            "frequency" : "2",
            "drift" : "0",
            "ipaddresspool" : "pub_1",
            "deleted" : true,
            "scores" : [
                { "score-group" : "redteam", "points" : "-13", "onsuccess" : "false" },
                { "score-group" : "blueteam", "points" : "13", "onsuccess" : "true" }
                ]
        }

    @apiError (Error 4xx) EventNotFound No event for this uuid
    @apiError (Error 5xx) EventNotUpdated Could not delete event
    @apiErrorExample Error-Response (example):
        HTTP/1.1 404 NOT FOUND
        {
            "error" : "EventNotFound"|"EventNotUpdated"
        }
=end
        put '/events/:eventuid/' do

            request.body.rewind
            eventRecord = nil
            eventObj = nil
            teamParent = nil

            begin
                data = JSON.parse request.body.read


                $appCore.teams.each do |team|
                    teamParent = team
                    #Iterate through each list of events of the team
                    team.singletonList.each do |event|
                        if event.eventuid == params[:eventuid]
                            eventObj = event
                            break
                        end
                    end
                    if eventRecord.nil?
                        team.periodicList.each do |event|
                            if event.eventuid == params[:eventuid]
                                eventObj = event
                                break
                            end
                        end
                    end
                end

                if eventObj.nil?
                    res = [404, {:error=>"EventNotFound"}.to_json]
                else

                    if data["deleted"] == false
                        eventObj.setundeleted()
                        $appCore.INBOX << GMessage.new({:fromid=>'WebClient',:signal=>'LOG',:msg=>"Event Marked UnDeleted: #{eventObj.eventuid}"})
                    end

                    eventObj.update(data);

                    #Collapse the event to a hash for output
                    eventhash = eventObj.wshash
                    eventhash[:teamid] = teamParent.teamid
                    eventRecord = eventhash

                    res = JSON.generate(eventRecord)
                    $appCore.INBOX << GMessage.new({:fromid=>'WebClient',:signal=>'LOG',:msg=>"Event Updated: #{eventRecord[:uuid]}"})

                end

            rescue ArgumentError=>e
                res = [422, {:error=>"invalidValuesError"}.to_json]
            rescue JSON::ParserError=>e
                res = [400, {:error=>"invalidInputError"}.to_json]
            end

            #Output the response
            res
        end

    end #End Class

end #End Module
