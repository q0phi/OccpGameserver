$LOAD_PATH.unshift(File.dirname(__FILE__))
#Dir[File.dirname(__FILE__) + '/lib/*.rb'].each {|file| require file }

require "OCCPGameServer/version"
require "OCCPGameServer/main"
require "OCCPGameServer/gameclock"
require "OCCPGameServer/team"
require "OCCPGameServer/Handlers/handler"
require "OCCPGameServer/Handlers/exechandler"
require "OCCPGameServer/Handlers/metasploithandler"
require "OCCPGameServer/Events/event"
require "OCCPGameServer/Events/execevent"
require "OCCPGameServer/Events/metasploitevent"
#require "OCCPGameServer/"
require "GameServerConfig"

require "log4r"
require "optparse"
require "libxml"
require "time"
#require "eventmachine"
#require "amqp"

require "colorize"


module OCCPGameServer
  
    include LibXML

    # Your code goes here...
    def self.ipsum
        $log.debug("Setting up function")
        puts "Hello World!"
    end

    # Parse a Team block
    # This means that the team itself should be parsed
    # each of it's events should be bundled and parsed separately
    def self.parse_team(newteamxmlnode)

        new_team = Team.new

        new_team.teamname = newteamxmlnode.attributes["name"]
        new_team.teamhost = newteamxmlnode.find('team-host').first.attributes["hostname"]
        new_team.speedfactor = newteamxmlnode.find('speed').first.attributes["factor"]

        newteamxmlnode.find('team-event-list').each{ |eventnode|
            new_team.add_raw_event(eventnode)
        }

        return new_team
    end

    # Takes an instance configuration file and returns an instance of the core application. 
    def self.instance_file_parser(instancefile)

        instance_parser = XML::Parser.file(instancefile)
        doc = instance_parser.parse

        #Do something with challenge metadata
        scenario_node = doc.find('/occpchallenge/scenario/name').first
        if scenario_node.nil? or scenario_node.content.length <1 then
            puts "Challenge name cannot be blank"
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
            rescue
               error = "Warning Handler Not Found: " + el_hash[:"class-handler"]
               puts error.red
               $log.warn(error)
            end
           
           main_runner.add_handler(handler_class)
        }

        # Load each team by parsing
        doc.find('/occpchallenge/team').each { |node|
            print "Parsing Team: " + node.attributes["name"] + " ... "
            $stdout.flush
            begin
                new_team = parse_team(node)    
            rescue
                puts "Warning Team Syntax Error".red
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

    opt_parser = OptionParser.new do |opt|
        opt.banner = "Usage: gameserver"
        opt.separator ""
        opt.separator "Commands"
        opt.separator ""
        opt.separator "Options"

        opt.on("-l","--logfile filename", "create the logfile using the given name") do |logfile|
            options[:logfile] = logfile
        end

        opt.on("-f","--instance-file filename", "game configuration file") do |gamefile|
            options[:gamefile] = gamefile
        end

        opt.on("-h","--help", "help") do
            puts opt_parser
        end
    end

    opt_parser.parse!

    #Setup default logging or use given log file name
    $log = Log4r::Logger.new('GameInstanceLog')
   
    fileoutputter = Log4r::FileOutputter.new('GameServer', {:trunc => true , :filename => options[:logfile]})
    fileoutputter.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d : %m")
    $log.outputters = fileoutputter
    
    $log.info("Begging new GameLog")

    #Decide if this will be the master or a slave agent
    if options[:gamefile] 
        $log.info("GameServer master mode")

        
        #Parse given instance file
        $log.debug("Opening instance file located at: " + options[:gamefile])
        
        # Process the instance file and get the app core class
        main_runner = instance_file_parser(options[:gamefile])


        # Launch my host listening thread
        #
        # puts GameServerConfig::Listen_address

        main = Thread.new { main_runner.run }

        # Handle user tty
        #
        while false do
            puts "Enter Q to exit or S for status"
            u_input = gets.chomp

            case u_input.upcase
            when "Q"
                main.exit
                break
            when "S"
                puts main.status
            end
        end

        main.join

    else
        $log.info("GameServer slave mode")

        #Open listening socket and wait...

    end
    
    
    
end

