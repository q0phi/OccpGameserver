$LOAD_PATH.unshift(File.dirname(__FILE__))

#Dir[File.dirname(__FILE__) + '/*.rb'].each {|file| require file }
#Dir["#{File.dirname(__FILE__)}/**/*.rb"].each { |f| require f }
#Dir["#{File.dirname(__FILE__)}/OCCPGameServer/**/*.rb"].each { |f| require f }
#Gem.find_files("OCCPGameServer/**/*.rb").each { |path| require path }

require "GameServerConfig"
require "log4r"
require "optparse"
require "libxml"
require "time"
require 'thread'
require 'sqlite3'
require "highline"
require "colorize"
require 'securerandom'
require 'simple-random'
require 'netaddr'
require 'net/smtp'
require 'net/scp'
require 'mysql2'

require "OCCPGameServer/version"
require "OCCPGameServer/main"
require "OCCPGameServer/gameclock"
require "OCCPGameServer/team"
require "OCCPGameServer/gmessage"
require "OCCPGameServer/score"
require "OCCPGameServer/iptools"
require "OCCPGameServer/webservices"
require "OCCPGameServer/libwrapper"
require "OCCPGameServer/errors"
require "OCCPGameServer/Handlers/handler"
require "OCCPGameServer/Handlers/exechandler"
require "OCCPGameServer/Handlers/metasploithandler"
require "OCCPGameServer/Handlers/nagiospluginhandler"
require "OCCPGameServer/Handlers/emailhandler"
require "OCCPGameServer/Handlers/scphandler"
require "OCCPGameServer/Handlers/dbhandler"
require "OCCPGameServer/Events/event"
require "OCCPGameServer/Events/execevent"
require "OCCPGameServer/Events/metasploitevent"
require "OCCPGameServer/Events/nagiospluginevent"
require "OCCPGameServer/Events/emailevent"
require "OCCPGameServer/Events/scpevent"
require "OCCPGameServer/Events/dbevent"

module OCCPGameServer
    #Challenge Run States
    WAIT = 1
    READY = 2
    RUN = 3
    STOP = 4
    QUIT = 5

    String.disable_colorization = false

    include LibXML

    $appCore = nil;

    # Takes an instance configuration file and returns an instance of the core application. 
    def self.instance_file_parser(instancefile)

        instance_parser = XML::Parser.file(instancefile)
        XML.default_line_numbers = true
        doc = instance_parser.parse

        userMenu = HighLine.new

        #Do something with challenge metadata
        scenario_node = doc.find('/occpchallenge/scenario').first
        if scenario_node.nil? then
            $log.warn("Error found in file #{instancefile}: #{scenario_node.line_num.to_s} - scenario section not defined".yellow)
        else
            scenario_name = scenario_node["name"]
            $log.info 'Scenario Name: ' + scenario_name
        end

        #Setup the main application
        main_runner = Main.new

        main_runner.scenarioname = scenario_name
        
        main_runner.gameid = doc.find('/occpchallenge/scenario').first["gameid"]
        $log.info "Game ID: " + main_runner.gameid
        main_runner.type = doc.find('/occpchallenge/scenario').first["type"]
        $log.info "Game type: " + main_runner.type
        main_runner.description = doc.find('/occpchallenge/scenario').first["description"]
        $log.info "Game description: " + main_runner.description

        #Setup the game clock
        length_node = doc.find('/occpchallenge/scenario/length').first
        begin
            #Error check
            scenarioLength = Integer(length_node["time"])
            scenarioLengthFormat = length_node["format"].to_s
            if not ["seconds", "minutes", "hours"].include?(scenarioLengthFormat) then
                throw ArgumentError
            end
        rescue Exception=>e
            $log.error("Error found in file #{instancefile}: #{scenario_node.line_num.to_s} - scenario length not defined".red)
            userMenu.say("Scenario length is not defined correctly!")
            scenarioLength = userMenu.ask("Enter scenario length in minutes? ", Integer)
            scenarioLengthFormat = "minutes"
        end

        main_runner.gameclock = GameClock.new
        main_runner.gameclock.set_gamelength(scenarioLength, scenarioLengthFormat)
        $log.info "Game Length: " + main_runner.gameclock.gamelength.to_s + " seconds"

        main_runner.networkid = doc.find('/occpchallenge/scenario/networkid').first["number"]
        $log.info "Network ID: " + main_runner.networkid


        #load the network map
        doc.find('host').each do |host|
            hostAttrs = host.attributes.to_h.inject({}){ |lh,(k,v)| lh[k.to_sym] = v; lh }
            if hostAttrs[:label] == "gameserver"
                $log.debug "gameserver Host tag found at: #{instancefile}: #{host.line_num.to_s}"
                host.find('interface').each do |interface|
                    main_runner.interfaces << interface.attributes.to_h.inject({}){ |lh,(k,v)| lh[k.to_sym] = v; lh }
                end
            end
        end

        # Create the IP address pools
        ip_pools = doc.find('ip-pools').first
        ip_pools.each_element do |pool|
            poolHash = pool.attributes.to_h
            poolHash = poolHash.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
            
            definedPool = main_runner.interfaces.find{|interface| poolHash[:network] == interface[:network]}
            if definedPool == nil
                    msg = "WARNING in file #{instancefile}: #{pool.line_num.to_s} - No defined interfaces for network #{poolHash[:network]} in address pool #{poolHash[:name]}"
                    $log.warn(msg.to_s.light_yellow)
                    puts msg.to_s.light_yellow
                    poolIfName = nil
            else
                poolIfName = definedPool[:name]
            end

            poolHash.merge!({:ifname => poolIfName})
            poolHash.merge!({:addresses => Array.new})

            pool.each_element do |addrDef|
                addrHash = addrDef.attributes.to_h
                addrHash = addrHash.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
           
                begin
                    case addrHash[:type] 
                    when 'range' 
                        poolHash[:addresses] += IPTools.generate_address_list(addrHash)
                    when 'list'
                        # Decode the content block as CSV addresses
                        if !addrDef.empty?
                            addrArray = addrDef.content.split(',')
                            addrArray.each do |addr|
                                addr.strip!
                                # TODO check that the addr is valid
                                #addr.regexmatch('')
                                poolHash[:addresses] << addr
                            end
                        end
                    end
                rescue Exception=>e
                    msg = "Error found in file #{instancefile}: #{addrDef.line_num.to_s} - #{e.message}"
                    $log.error(msg.to_s.red)
                    puts msg.to_s.red
                    exit(1)
                end
            end
            poolHash[:addresses].uniq!
            main_runner.ipPools.merge!(poolHash[:name] => poolHash)
        end

   #    # Register the team host locations (minimally localhost)
   #      team_node = doc.find('/occpchallenge/team-hosts').first
   #      team_node.each_element do |element| 
   #          el_hash = element.attributes.to_h
   #          el_hash = el_hash.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}

   #          # Setup the team host in the MP registry 
   #          $log.info "New Team Host: " + el_hash[:name]

   #          main_runner.add_host(el_hash)
   #      end
           
                
        #Instantiate the event-handlers for this scenario
        eventhandler_node = doc.find('/occpchallenge/event-handlers').first
        eventhandler_node.each_element {|element|
            el_hash = element.attributes.to_h
            el_hash = el_hash.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
            
            $log.debug "Request Handler: " + el_hash[:"class-handler"]
          
            begin
                handler_class = OCCPGameServer.const_get(el_hash[:"class-handler"]).new(el_hash)
                main_runner.add_handler(handler_class)

            rescue
               error = "Handler Not Found: " + el_hash[:"class-handler"] + " class file may be missing."
               $log.warn(error)
            end
           
        }
        
        # Load each team by parsing
        $log.info('Parsing Team Data...')
        i=1
        doc.find('/occpchallenge/team').each { |teamxmlnode|
            $log.debug "Parsing Team: " + teamxmlnode.attributes["name"] + "..."
            begin

                new_team = Team.new

                #TODO Decide if this needs fixing
                new_team.teamid = SecureRandom.uuid
                i += 1
                new_team.teamname = teamxmlnode.attributes["name"]
                new_team.teamhost = teamxmlnode.find('team-host').first.attributes["hostname"]
                new_team.speedfactor = teamxmlnode.find('speed').first.attributes["factor"]

                teamxmlnode.find('team-event-list').each{ |eventlist|
                    
                    #Validate each event
                    eventlist.find('team-event').each {|event|
                            
                        #First Identify the handler
                        handler_name = event.attributes["handler"]
                        event_handler = main_runner.get_handler(handler_name)
                        raise ArgumentError, "Error found in file #{instancefile}: #{event.line_num.to_s} - handler #{handler_name} not defined" if event_handler.nil?
                       

                        begin
                            this_event = event_handler.parse_event(event, main_runner)
                        rescue ArgumentError=>e
                            raise ArgumentError, "Error found in file #{instancefile}: #{event.line_num.to_s} - #{e.message}"
                        end
                       
                        #Split the list into periodic and single events
                        if this_event.frequency.eql?(0.0)
                            new_team.singletonList << this_event
                            $log.debug "Added single event #{this_event.name} to #{new_team.teamname}"
                        else
                            new_team.periodicList << this_event
                            $log.debug "Added periodic event #{this_event.name} to #{new_team.teamname}"
                        end

                    }
            
                }

            rescue ArgumentError => e
                $log.fatal(e.to_s.red)
                puts e.to_s.red
                exit(1)
            else
                $log.debug "Parsing Team: " + teamxmlnode.attributes["name"] + "... Complete"
            end

            main_runner.add_team(new_team)

        }

        #Take care of scorekeeping
        scoreKeeper = main_runner.scoreKeeper
        
        $log.info('Parsing Score Data...')
        scoreblock = doc.find('/occpchallenge/scenario/score-labels').first
        scoreblock.each_element { |label|
            
            # Integrity checks
            name = label.attributes["name"]; sql = label.attributes["sql"]

            raise ArgumentError, 'Argument label-name cannot be blank' if name.nil? || name.empty?
            
            if sql.nil? || sql.empty?
                sql = "SELECT SUM(value) FROM SCORE WHERE groupname='#{name}'"
            end

            begin
                res = $db.prepare(sql)
                num_cols = res.columns().count
                
                raise ArgumentError, "SQL statement returned #{num_cols} cols, expecting 1 column" if num_cols != 1

            rescue SQLite3::SQLException, ArgumentError => e
                msg = 'Error found in file '+ instancefile + ':' + label.line_num.to_s + ' - ' + e.to_s
                puts msg.red
                $log.fatal msg.red
                exit(1)
            end
            
            tempT = scoreKeeper.ScoreLabel.new(name, sql, res)

            scoreKeeper.labels.push( tempT )
        }
        scoreblock = doc.find('/occpchallenge/scenario/score-names').first
        scoreblock.each_element { |name|
            $log.debug "Parsing Score Name: " + name.attributes["name"]
            tempT = scoreKeeper.ScoreName.new(name.attributes["name"], name.attributes["formula"], name.attributes["descr"])
            scoreKeeper.names.push( tempT )
        }

        
        return main_runner

    end
   
    log = Log4r::Logger.new('occp')
    loglevels = log.levels.inject(' ') {|accum, item| accum += "#{log.levels.index(item)}=#{item} "}

    #Setup and parse command line parameters
    $options = {}
    $options[:logfile] = "gamelog.txt" #" + Time.new.strftime("%Y%m%dT%H%M%S") + ".txt"
    $options[:loglevel] = 2 
    $options[:datafile] = "gamedata.db" #" + Time.new.strftime("%Y%m%dT%H%M%S") + ".db"

    opt_parser = OptionParser.new do |opt|
        opt.banner = "Usage: occpgs --instance-file instance.xml [options]"
        opt.separator ""
        opt.separator "Required:"
        opt.on("-f","--instance-file filename", "Scenario configuration file") do |gamefile|
            $options[:gamefile] = File.expand_path( gamefile, Dir.getwd) # File.dirname(__FILE__))
        end
        
        opt.separator "Optional:"
        opt.separator ""
        opt.on("-l","--logfile filename", "File name of log file") do |logfile|
            filename = $options[:logfile]
            if File.directory?(logfile)
                $options[:logfile] = File.join(logfile,filename)
            else    
                $options[:logfile] = logfile
            end
        end

        opt.on("--log-level integer", Integer, "Set the verbosity level of the log file,", "[#{loglevels}]") do |loglevel|
            if not loglevel.nil?
                begin
                    Log4r::Log4rTools.validate_level(loglevel) 
                    $options[:loglevel] = loglevel
                rescue
                    # levels = Log4r::Log4rTools.max_level_str_size
                    puts "Log level not in [#{loglevels}]"
                    exit
                end
            end
                
        end

        opt.on("-d","--database filename", "File name of the database for event and score records") do |datafile|
            filename = $options[:datafile] 
            
            if File.directory?(datafile)
                fp = File.join(datafile,filename)
                if File.exist?(fp)
                    File.delete(fp)
                end
                $options[:datafile] = fp

            else    
                $options[:datafile] = datafile
            end

        end

        opt.separator ""
        opt.on_tail("-h","--help", "Show this help information") do
            puts opt
            exit
        end
        
        opt.on_tail("--version", "Show version") do
            puts "Open Cyber Challenge Platform"
            puts "http://www.opencyberchallenge.net"
            puts "Gameserver Application Version  occpgs-#{OCCPGameServer::VERSION}"
            exit
        end
    end

    begin
        opt_parser.parse!
    rescue OptionParser::MissingArgument, OptionParser::InvalidArgument=>e
        puts e.message
        puts opt_parser
        exit
    end

    #Setup default logging
    $log = Log4r::Logger.new('occp::gameserver::instancelog', $options[:loglevel])
    #$log.trace = true

    # Output to the filepath given
    fileoutputter = Log4r::FileOutputter.new('GameServer', {:trunc => true , :filename => $options[:logfile]})
    fileoutputter.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d %x %m")
    
    Log4r::NDC.push('OCCP GS:')
    
    $log.outputters = [fileoutputter]
    
    $log.info("Begining new GameLog")

    #Decide if this will be the master or a slave agent
    if $options[:gamefile] 
        $log.info("GameServer master mode")

        
        #Parse given instance file
        $log.debug("Opening instance file located at: " + $options[:gamefile])
        
        #Create the database for this run
        begin

            $db = SQLite3::Database.new($options[:datafile])

            #pre-populate the table structure
            dbschema = File.open(File.dirname(__FILE__)+'/../schema.sql', 'r')
            
            $db.execute_batch dbschema.read
        

            #puts db.execute "SELECT * FROM sqlite_master WHERE type='table'"
            $log.info("Database Created and Initialized")

            #main_runner.db = db

        rescue SQLite3::Exception => e
            $log.error("Database Initiation Error")
            $log.error( e )
        end

        # Process the instance file and get the app core class
        $appCore = instance_file_parser($options[:gamefile])

        #Launch the main application
        main = Thread.new { $appCore.run() }
  
        #Launch the Web Services
        web = Thread.new { WebListener.run! }

        #Wait for Sinatra to start completely
        sleep(1)

        #Setup the menuing system
        highL = HighLine.new
        highL.page_at = :auto

        # Handle user terminal
        userInterface = Thread.new {
            exitable = false
            while not exitable do
                highL.choose do |menu|
                    menu.header = "==================================\nSelect from the list below"
                    menu.choice(:"Start"){
                        highL.say("==================================\n")
                        currentStatus = $appCore.STATE
                        case currentStatus
                        when STOP
                            highL.say("Game is Stopped. Only Status can be shown.")
                        else
                            $appCore.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> RUN}})
                        end
                    }
                    menu.choice(:"Pause"){
                        highL.say("==================================\n")
                        currentStatus = $appCore.STATE
                        case currentStatus
                        when STOP
                            highL.say("Game is Stopped. Only Status can be shown.")
                        else
                            $appCore.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> WAIT}})
                        end
                    }
                    menu.choice(:Status) {
                        highL.say("==================================\n")
                        
                        # Notify the system to emit status messages
                        $appCore.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'STATUS', :msg=>{}})
                        
                        currentStatus = $appCore.STATE
                        case currentStatus
                            when RUN
                                highL.say("All Teams are Running")
                            when WAIT
                                highL.say("Teams are Paused")
                            when STOP
                                highL.say("Game is Stopped")
                        end

                        gTime = Time.at($appCore.gameclock.gametime).utc.strftime("%H:%M:%S")
                        gLength = Time.at($appCore.gameclock.gamelength).utc.strftime("%H:%M:%S")
                        highL.say("Current Gametime is: #{gTime} of #{gLength}")

                        $appCore.scoreKeeper.get_names.each{ |scoreName|
                            highL.say(scoreName + ': ' + $appCore.scoreKeeper.get_score(scoreName).to_s )
                        }

                        
                    }
                    menu.choice(:"Clear Screen") {
                        system("clear")
                    }
                    menu.choice(:Quit) {
                        #if highL.agree("Confirm exit? ", true)
                            highL.say("Exiting...")
                            $appCore.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> QUIT}})
                            exitable = true
                        #end
                    }
                    menu.prompt = "Enter Selection: "
                end

            end
        }
        
         
        # Wait for Children to exit
        if userInterface.alive?
            $log.debug "Waiting to shutdown UI."
            userInterface.join
            $log.debug "Shutdown UI complete."
        end
        if main.alive?
            $log.debug "Waiting to shutdown main."
            main.join
            $log.debug "Shutdown main complete."
        end

        #Log final times
        if  $appCore.endtime != nil and $appCore.begintime != nil
            totalgametime = $appCore.endtime - $appCore.begintime
            $log.info "Total game length: #{'%.2f' % totalgametime} sec"
            $log.info "Total time paused: #{'%.2f' % (totalgametime - $appCore.gameclock.gametime)} sec"
        else
            $log.info "Total game length: NO TIME"
        end
        #Log final scores
        $appCore.scoreKeeper.get_names.each{ |scoreName|
            $log.info("Score " + scoreName + ': ' + $appCore.scoreKeeper.get_score(scoreName).to_s)
        }

        #Cleanup and Close Files
        $appCore.scoreKeeper.cleanup #close prepared transactions
        $db.close

        $log.info "GameServer shutdown complete"

    else
        $log.info "GameServer slave mode"

        #Open listening socket and wait...

    end
    
end
