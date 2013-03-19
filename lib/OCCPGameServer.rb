require "OCCPGameServer/version"
require "log4r"
require "optparse"
require "xml"


module OCCPGameServer
  
    # Your code goes here...
    def self.ipsum
        $log.debug("Setting up function")
        puts "Hello World!"
    end

   
    def self.instance_file_parser(instancefile)

        $log.debug("Opening instance file located at: " + instancefile)


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
        instance_file_parser(options[:gamefile])

    else
        $log.info("GameServer slave mode")

        #Open listening socket and wait...

    end
    
    
    
end

