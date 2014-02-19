module OCCPGameServer

    class Main

        attr_accessor :gameclock, :networkid, :scenarioname, :INBOX, :eventRunQueue
        attr_accessor :STATE, :db

        #Challenge Run States
        WAIT = 1
        READY = 2
        RUN = 3
        STOP = 4


        def initialize
            @events = {}
            @hosts = Array.new
            
            @teams = Array.new
            @localteams = Array.new
            
            #Run queue for event that have been launched by a ascheduler
            @eventRunQueue = Queue.new
            
            @INBOX = Queue.new

            @db = ''

            @handlers= Array.new

            @gameclock = GameClock.new

            @STATE = WAIT
        end

        def add_event()
        end

        #Add a team host to the list
        def add_host(new_host)
            @hosts.push(new_host)
        end
        
        def add_team(new_team)
            @teams.push(new_team)
        end
        
        #Store each of the event handlers to be dispatched
        def add_handler(new_handler)
            @handlers.push(new_handler)
        end

        # Lookup a handler by name to get its information
        def get_handler(handle_name)
            
            @handlers.each {|handler|
                if handler.name == handle_name
                    return handler
                end
            }
            return handle_name
        end
        
        def get_handlers()
            @handlers
        end

        def set_state(state)

            case state
                when WAIT
                    if @STATE == RUN
                        @teams.each { |team|
                            team.set_state(state)
                    }
                    end
                when RUN
                    @teams.each { |team|
                            team.set_state(state)
                    }
            end


            @STATE = state
        end
        def get_state()
            return @STATE
        end
        
        # Entry point for the post-setup code
        def run ()

            #create a taskmaster that will pop events off the main queue and spin them into worker threads
            '''
                @taskmaster = Thread.new{ 
            
                workerthreads = []
                
                while true do
                
                    if @STATE === WAIT
                       sleep 1
                       next
                    end

                    nextevent = @eventRunQueue.pop

                    workerthreads << Thread.new{
                        #do something with each nextevent
                        puts nextevent.name.to_s.blue
                    }
                end

                workerthreads.each { |wthread| wthread.join }
            }
            '''
            #Launch each teams scheduler
            @teams.each { |team|
                if team.teamhost == "localhost" 
                    @localteams << {:teamid=>team.teamid, :thr=> Thread.new { team.run(self) }}
                else
                    #lookup the connection information for this team and dispatch the team
                end

            }
            
            #Poll the @INBOX waiting for tasks
            while message = @INBOX.pop do

                case message.signal
                
                when 'CONSOLE'
                    #Dump Messages to the Screen and into the logfile
                  #  puts message.fromid.to_s.yellow + " " + message.msg.to_s
                    $log.info(message.fromid.to_s + ": " + message.msg.to_s)

                when 'SCORE'
                    #We are receiving a score hash that should be added to the appropriate score group
                    timeT = Time.now.to_i
                    group = message.msg[:scoregroup]
                    value = message.msg[:value]
                    eventuid = message.msg[:eventuid]

                    $db.execute("INSERT INTO score VALUES (?,?,?,?)", [timeT, eventuid, group, value])
                    $log.info("Score recorded in db.score")

               
                when 'EVENTLOG'
                    #Log that an event was run       
                    tblArray = [Time.now.to_i, 
                        message.msg[:handler], 
                        message.msg[:eventname], 
                        message.msg[:eventuid], 
                        message.msg[:custom], 
                        message.msg[:status] 
                    ]

                    $db.execute("INSERT INTO event VALUES (?,?,?,?,?,?);", tblArray);
                    $log.info("Event Recorded in db.event")

                when 'COMMAND'

                    command = message.msg
                    
                    case command[:command]
                    when 'STATE'
                        set_state(command[:state])
                    end


                when 'DIE'
                    break
                else
                    break
                end

            end #@INBOX Poll

            #wait for all the teams to finish
            @localteams.each { |team| team[:thr].join }
            #@taskmaster.join

        end #def run



    end #Class
  
end #Module
