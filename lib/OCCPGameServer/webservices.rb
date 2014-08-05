module OCCPGameServer

    require 'sinatra/base'
    require'json'
    
    class WebListener < Sinatra::Base
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
=begin
    @api {get} / Request System Information
    @apiVersion 0.1.0
    @apiName Root
    @apiGroup System

    @apiSuccess {String} application Name of the application
    @apiSuccess {String} version Version of the application
    
    @apiSuccessExample Success-Response:
        HTTP/1.1 200 OK
        {
            "application" : "OCCP GameServer",
            "version" : "1.0.0"
        }
     
=end
        get '/' do
            info = {:Application => "OCCP GameServer", :Version => OCCPGameServer::VERSION}
            JSON.generate(info)
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
    
    @apiSuccessExample Success-Response:
        HTTP/1.1 200 OK
        {
            "name" : "Red Team v. Blue Team",
            "id" : "1",
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
                        :description => $appCore.description
            }
            JSON.generate(info)
        end

=begin
    @api {get} /gameclock/ Read the game clock
    @apiVersion 0.1.0
    @apiName GetGameclock
    @apiGroup Gameclock

    @apiSuccess {Number} length Length of the scenario in seconds
    @apiSuccess {Number} gametime Current value of the game clock in seconds
    @apiSuccess {String} state The current state of the game clock

    @apiSuccessExample Success-Response:
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
        get '/gameclock/states/' do
            info = {
                    :length => $appCore.gameclock.gamelength,
                    :gametime => $appCore.gameclock.gametime,
                    :state => @@game_states[$appCore.STATE]
            }
            JSON.generate(@@game_states)
        end

=begin
    @api {get} /teams/ Read all teams
    @apiVersion 0.1.0
    @apiName GetTeams
    @apiGroup Teams

    @apiSuccess {String} name Name of the team
    @apiSuccess {String} id Id of the team

    @apiSuccessExample Success-Response:
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

    @apiSuccessExample Success-Response:
        HTTP/1.1 200 OK
        {
            "name" : "Blue Team",
            "id" : "1235-1235-1235",
            "rate" : "1.0",
            "state" : "WAIT"
        }
    @apiError (Error 4xx) TeamNotFound The team for the given id was not found
    @apiErrorExample Error-Response:
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
    @apiVersion 0.1.0
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
    @apiSuccess {Object[]} events.scores Score items associated with this event
    @apiSuccess {String} events.scores.scoregroup Score group label for this score
    @apiSuccess {String} events.scores.points Number of points to assign for this score
    @apiSuccess {Boolean} events.scores.onsuccess Whether to assign points when event succeeds or fails


    @apiSuccessExample Success-Response:
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
                    "scores" : [	
                        { "score-group" : "redteam", "points" : "-13", "onsuccess" : "false" },
                        { "score-group" : "blueteam", "points" : "13", "onsuccess" : "true" }
                        ]
                },
                . . .
                ]
        }

    @apiError (Error 4xx) TeamNotFound The team for the given id was not found
    @apiErrorExample Error-Response:
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
    @apiVersion 0.1.0
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
    @apiSuccess {Object[]} scores Score items associated with this event
    @apiSuccess {String} scores.scoregroup Score group label for this score
    @apiSuccess {String} scores.points Number of points to assign for this score
    @apiSuccess {Boolean} scores.onsuccess Whether to assign points when event succeeds or fails


    @apiSuccessExample Success-Response:
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
            "scores" : [	
                { "score-group" : "redteam", "points" : "-13", "onsuccess" : "false" },
                { "score-group" : "blueteam", "points" : "13", "onsuccess" : "true" }
                ]
        }

    @apiError (Error 4xx) TeamNotFound The team for the given id was not found
    @apiError (Error 4xx) EventNotFound The event for the given id was not found
    @apiErrorExample Error-Response:
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
    end #End Class

end #End Module
