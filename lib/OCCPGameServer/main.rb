module OCCPGameServer

    class Main

        attr_accessor :gameclock, :networkid, :scenarioname

        def initialize
            @events = {}
            @hosts = Array.new
            
            @teams = Array.new
            @localteams = Array.new
            
            @score = []

            @handlers= Array.new
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
            return false
        end
        
        def get_handlers()
            @handlers
        end
        
        def record_score()
        end
        
        def dispatch_team(team)

        end

        # Entry point for the post-setup code
        def run ()


            #Scan each of the teams and dispatch them as neccessary
            @teams.each { |team|
                if team.teamhost == "localhost" 
                    @localteams << Thread.new { team.run(self) }
                else
                    #lookup the connection information for this team and dispatch the team
                end

            }

            #wait for all the teams to finish
            @localteams.each { |team| team.join }

        end



    end
  
end
