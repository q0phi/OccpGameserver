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
        doc = instance_parser.parse

        #Do something with challenge metadata
        scenario_node = doc.find('/occpchallenge/scenario/name').first
        if scenario_node.nil? or scenario_node.content.length <1 then
            $log.error('Instance File Error: Challenge name cannot be blank')
        else
            scenario_name = scenario_node.content
            puts scenario_name
        end

        #Setup the main application
        main_runner = Main.new

        main_runner.scenarioname = scenario_name

        #Setup the game clock
        length_node = doc.find('/occpchallenge/scenario/length').first
       
        main_runner.gameclock = GameClock.new
        main_runner.gameclock.set_gamelength(length_node["time"],length_node["format"])
        puts "Game Length: " + main_runner.gameclock.gamelength.to_s

        main_runner.networkid = doc.find('/occpchallenge/scenario/networkid').first["number"]
        puts "Network ID: "+main_runner.networkid


        #Register the team host locations (minimally localhost)
        team_node = doc.find('/occpchallenge/team-hosts').first
        team_node.each_element {|element| 
            el_hash = element.attributes.to_h
            el_hash = el_hash.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}

            # Setup the team host in the MP registry 
            puts "New Team Host: " + el_hash[:name]

            main_runner.add_host(el_hash)
        }
           
                
        #Instantiate the event-handlers for this scenario
        eventhandler_node = doc.find('/occpchallenge/event-handlers').first
        eventhandler_node.each_element {|element|
            el_hash = element.attributes.to_h
            el_hash = el_hash.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
            
            puts "Request Handler: " + el_hash[:"class-handler"]
          
            begin
               handler_class = OCCPGameServer.const_get(el_hash[:"class-handler"]).new(el_hash)

               # if !handler_class.nil? 
                    main_runner.add_handler(handler_class)
                #end

            rescue
               error = "Warning Handler Not Found: " + el_hash[:"class-handler"]
               $log.warn(error)
            end
           
        }

        # Load each team by parsing
        $log.info('Parsing Team Data...')
        doc.find('/occpchallenge/team').each { |teamxmlnode|
            print "Parsing Team: " + teamxmlnode.attributes["name"] + " ... "
            $stdout.flush
            begin

                new_team = Team.new

                new_team.teamid = SecureRandom.uuid
                new_team.teamname = teamxmlnode.attributes["name"]
                new_team.teamhost = teamxmlnode.find('team-host').first.attributes["hostname"]
                new_team.speedfactor = teamxmlnode.find('speed').first.attributes["factor"]

                teamxmlnode.find('team-event-list').each{ |eventlist|
                    
                    #Validate each event|
                    eventlist.find('team-event').each {|event|
                            
                        #First Identify the handler
                        handler_name = event.find("handler").first.attributes["name"]
                       
                        event_handler = main_runner.get_handler(handler_name)

                        this_event = event_handler.parse_event(event)

                        #Split the list into periodic and single events
                        if this_event.freqscale === 'none'
                            new_team.singletonList << this_event
                        else
                            new_team.periodicList << this_event
                        end

                    }
            
                }

            rescue ArgumentError => e
                $log.error(e.message)
                puts e.message.red
                exit(1)
            else
                puts "done."
            end

            main_runner.add_team(new_team)

        }


        return main_runner

    end
    
    #Setup and parse command line parameters
    options = {}
    options[:logfile] = "gamelog.log"
    options[:datafile] = "gamedata.db"# + Time.new.strftime("%Y%m%dT%H%M%S") + ".db"

    opt_parser = OptionParser.new do |opt|
        opt.banner = "Usage: gameserver"
        opt.separator ""
        opt.separator "Commands"
        opt.separator ""
        opt.separator "Options"

        opt.on("-l","--logfile filename", "create the logfile using the given name") do |logfile|
            filename = "gamelog.txt" #" + Time.new.strftime("%Y%m%dT%H%M%S") + ".txt"
            if File.directory?(logfile)
                options[:logfile] = File.join(logfile,filename)
            else    
                options[:logfile] = logfile
            end
        end

        opt.on("-f","--instance-file filename", "game configuration file") do |gamefile|
            options[:gamefile] = gamefile
        end
        
        opt.on("-s","--database filename", "game record database") do |datafile|
            filename = "gamedata.db" #-" + Time.new.strftime("%Y%m%dT%H%M%S") + ".db"
            
            if File.directory?(datafile)
                fp = File.join(datafile,filename)
                if File.exist?(fp)
                    File.delete(fp)
                end
                options[:datafile] = fp

            else    
                options[:datafile] = datafile
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
    fileoutputter = Log4r::FileOutputter.new('GameServer', {:trunc => true , :filename => options[:logfile]})
    fileoutputter.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d %x %m")
    
    Log4r::NDC.push('OCCP GS:')
    
    $log.outputters = [fileoutputter]
    
    $log.info("Begining new GameLog")

    #Decide if this will be the master or a slave agent
    if options[:gamefile] 
        $log.info("GameServer master mode")

        
        #Parse given instance file
        $log.debug("Opening instance file located at: " + options[:gamefile])
        
        # Process the instance file and get the app core class
        main_runner = instance_file_parser(options[:gamefile])

        #Create the database for this run
        begin

            $db = SQLite3::Database.new(options[:datafile])

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

        #Launch the main application
        main = Thread.new { main_runner.run }
    
        #Setup the menuing system
        hlMenu = HighLine.new
        hlMenu.page_at = :auto



        # Handle user tty
        exitable = false
        while not exitable do
            hlMenu.choose do |menu|
                menu.header = "Select from the list below"
                menu.choice(:Status) {
                    currentStatus = main_runner.STATE

                    case currentStatus
                        when RUN
                        hlMenu.say("All Teams are Running")
                        when WAIT
                            hlMenu.say("Teams are Paused")
                    end
                    
                }
                menu.choice(:"Start"){
                    #main_runner.set_state(Main::RUN)
                    main_runner.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> RUN}})
                }
                menu.choice(:"Pause"){
                    #main_runner.set_state(Main::WAIT)
                    main_runner.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> WAIT}})
                }
                menu.choice(:"Clear Screen") {
                    system("clear")
                }
                menu.choice(:Quit) {
                    #if hlMenu.agree("Confirm exit? ", true)
                        hlMenu.say("Exiting...")
                        main_runner.INBOX << GMessage.new({:fromid=>'CONSOLE',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> STOP}})
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

