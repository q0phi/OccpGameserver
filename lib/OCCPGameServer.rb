require "OCCPGameServer/version"
require "log4r"

module OCCPGameServer
  
    #Setup Logging
    log = Log4r::Logger.new('GameInstanceLog')
   
    fileoutputter = Log4r::FileOutputter.new('GameServer', {:trunc => true , :filename => 'gamelog.log'})
    fileoutputter.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d : %m")
    log.outputters = fileoutputter
    
    log.info("Begging new GameLog")

    #Decide if this will be the master or a slave agent
    log.debug("...")
    
    # Your code goes here...
    def self.ipsum
        log.debug("Setting up function")
        puts "Hello World!"
    end

    puts "Hello World! Raw"
    
end

