$LOAD_PATH.unshift(File.dirname(__FILE__))

#Dir[File.dirname(__FILE__) + '/*.rb'].each {|file| require file }
#Dir["#{File.dirname(__FILE__)}/**/*.rb"].each { |f| require f }
#Dir["#{File.dirname(__FILE__)}/OCCPGameServer/**/*.rb"].each { |f| require f }
#Gem.find_files("OCCPGameServer/**/*.rb").each { |path| require path }

require "OCCPGameServer/version"
require "OCCPGameServer/main"
require "OCCPGameServer/gameclock"
require "OCCPGameServer/team"
require "OCCPGameServer/gmessage"
require "OCCPGameServer/score"
require "OCCPGameServer/Handlers/handler"
require "OCCPGameServer/Handlers/exechandler"
require "OCCPGameServer/Handlers/metasploithandler"
require "OCCPGameServer/Events/event"
require "OCCPGameServer/Events/execevent"
require "OCCPGameServer/Events/metasploitevent"

require "GameServerConfig"
require "log4r"
require "optparse"
require "libxml"
require "time"
require 'thread'
require 'sqlite3'
require "highline"
require "colorize"

module OCCPGameServer
    #Challenge Run States
    WAIT = 1
    READY = 2
    RUN = 3
    STOP = 4

    include LibXML

    # Takes an instance configuration file and returns an instance of the core application. 
    def self.instance_file_parser(instancefile)
        require 'securerandom'

        instance_parser = XML::Parser.file(instancefile)
        XML.default_line_numbers = true
        doc = instance_parser.parse

        #Do something with challenge metadata
        scenario_node = doc.find('/occpchallenge/scenario/name').first
        if scenario_node.nil? or scenario_node.content.length <1 then
            $log.error('Instance File Error: Challenge name cannot be blank')
        else
            scenario_name = scenario_node.content
            $log.info 'Scenario Name: ' + scenario_name
        end

        #Setup the main application
        main_runner = Main.new

        main_runner.scenarioname = scenario_name

        #Setup the game clock
        length_node = doc.find('/occpchallenge/scenario/length').first
       
        main_runner.gameclock = GameClock.new
        main_runner.gameclock.set_gamelength(length_node["time"],length_node["format"])
        $log.info "Game Length: " + main_runner.gameclock.gamelength.to_s

        main_runner.networkid = doc.find('/occpchallenge/scenario/networkid').first["number"]
        $log.info "Network ID: " + main_runner.networkid


        #load the network map
        doc.find('host').each do |host|
            hostAttrs = host.attributes.to_h.inject({}){ |lh,(k,v)| lh[k.to_sym] = v; lh }
            if hostAttrs[:label] == "gameserver"
                host.find('interface').each do |interface|
                    main_runner.interfaces << interface.attributes.to_h.inject({}){ |lh,(k,v)| lh[k.to_sym] = v; lh }
                end
            end
        end
        
        #Register the team host locations (minimally localhost)
        team_node = doc.find('/occpchallenge/team-hosts').first
        team_node.each_element do |element| 
            el_hash = element.attributes.to_h
            el_hash = el_hash.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}

            # Setup the team host in the MP registry 
            $log.info "New Team Host: " + el_hash[:name]

            main_runner.add_host(el_hash)
        end
           
                
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
               error = "Handler Not Found: " + el_hash[:"class-handler"]
               $log.warn(error)

            end
           
        }
        
        # Load each team by parsing
        $log.info('Parsing Team Data...')
        doc.find('/occpchallenge/team').each { |teamxmlnode|
            $log.debug "Parsing Team: " + teamxmlnode.attributes["name"] + "..."
            begin

                new_team = Team.new

                new_team.teamid = SecureRandom.uuid
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
                            this_event = event_handler.parse_event(event)
                        rescue ArgumentError=>e
                            raise ArgumentError, "Error found in file #{instancefile}: #{event.line_num.to_s} - #{e.message}"
                        end
                       
                        #Split the list into periodic and single events
                        if this_event.frequency.eql?(0.0)
                            new_team.singletonList << this_event
                        else
                            new_team.periodicList << this_event
                        end

                    }
            
                }

            rescue ArgumentError => e
                $log.error(e.to_s.red)
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
                $log.error msg.red
                exit(1)
            end

            
            tempT = scoreKeeper.ScoreLabel.new(name, sql, res)
                #Score::ScoreLabel.new(label.attributes["name"], label.attributes["sql"] ) 

            scoreKeeper.labels.push( tempT )
        }
        scoreblock = doc.find('/occpchallenge/scenario/score-names').first
        scoreblock.each_element { |name|
            $log.debug "Parsing Score Name: " + name.to_s + " ... "
            tempT = scoreKeeper.ScoreName.new(name.attributes["name"], name.attributes["formula"], name.attributes["descr"])
            scoreKeeper.names.push( tempT )
        }

        
        return main_runner

    end
    
    #Setup and parse command line parameters
    $options = {}
    $options[:logfile] = "gamelog.log"
    $options[:datafile] = "gamedata.db"# + Time.new.strftime("%Y%m%dT%H%M%S") + ".db"

    opt_parser = OptionParser.new do |opt|
        opt.banner = "Usage: gameserver"
        opt.separator ""
        opt.separator "Commands"
        opt.separator ""
        opt.separator "$options"

        opt.on("-l","--logfile filename", "create the logfile using the given name") do |logfile|
            filename = "gamelog.txt" #" + Time.new.strftime("%Y%m%dT%H%M%S") + ".txt"
            if File.directory?(logfile)
                $options[:logfile] = File.join(logfile,filename)
            else    
                $options[:logfile] = logfile
            end
        end

        opt.on("-f","--instance-file filename", "game configuration file") do |gamefile|
            $options[:gamefile] = File.expand_path( gamefile, Dir.getwd) # File.dirname(__FILE__))
        end
        
        opt.on("-s","--database filename", "game record database") do |datafile|
            filename = "gamedata.db" #-" + Time.new.strftime("%Y%m%dT%H%M%S") + ".db"
            
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

        opt.on("-h","--help", "help") do
            puts opt_parser
        end
    end

    opt_parser.parse!



    #Setup default logging or use given log file name
    $log = Log4r::Logger.new('occp::gameserver::instancelog')
  # $log.trace = true
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
            dbschema = File.open('schema.sql', 'r')
            
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
        main = Thread.new { $appCore.run }
    
        #Setup the menuing system
        highL = HighLine.new
        highL.page_at = :auto

        #system('clear')

        # Handle user tty
        exitable = false
        while not exitable do
            highL.choose do |menu|
                menu.header = "==================================\nSelect from the list below"
                menu.choice(:Status) {
                    highL.say("==================================")
                    currentStatus = $appCore.STATE
                    
                    case currentStatus
                        when RUN
                            highL.say("All Teams are Running")
                        when WAIT
                            highL.say("Teams are Paused")
                    end
                    $appCore.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'STATUS', :msg=>{}})
             
             #       $appCore.scoreKeeper.labels.each{|label| 
             #           puts 'found: '.red + (label.get_sql.nil? ? '' : label.get_sql )
             #       }
             #       $appCore.scoreKeeper.names.each{|label| 
             #           puts 'found: '.red + label.to_s
             #       }
             #       $appCore.scoreKeeper.get_labels.each{ |scoreName|
             #           puts scoreName
             #       }
                    $appCore.scoreKeeper.get_names.each{ |scoreName|
                        highL.say(scoreName + ': ' + $appCore.scoreKeeper.get_score(scoreName).to_s )
                    }

                    
                }
                menu.choice(:"Start"){
                    #$appCore.set_state(Main::RUN)
                    $appCore.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> RUN}})
                }
                menu.choice(:"Pause"){
                    #$appCore.set_state(Main::WAIT)
                    $appCore.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> WAIT}})
                }
                menu.choice(:"Clear Screen") {
                    system("clear")
                }
                menu.choice(:Quit) {
                    #if highL.agree("Confirm exit? ", true)
                        highL.say("Exiting...")
                        $appCore.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> STOP}})
                        exitable = true
                    #end
                }
                menu.prompt = "Enter Selection: "
            end

        end

        main.join

        #Cleanup and Close Files
        
        $db.close

        $log.info "GameServer shutdown complete"

    else
        $log.info "GameServer slave mode"

        #Open listening socket and wait...

    end
    
    
    
end

