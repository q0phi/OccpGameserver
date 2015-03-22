module OCCPGameServer

    # This class handles all of the score calculations and what-nots
    class Score

        attr_accessor :labels, :names, :ScoreLabel, :ScoreName
        def initialize

            @ScoreLabel = Struct.new(:name, :raw_sql, :prepared_sql) do

                def get_sql
                    sql = "SELECT SUM(value) FROM SCORES WHERE groupname='#{name}'"
                    if not select.nil?
                        sql = "SELECT #{select} FROM SCORES"
                        if not where.nil?
                            sql += " WHERE #{where}"
                        end
                    elsif not calculation.nil?
                        sql = calculation
                    end
                    sql
                end
            end

            @ScoreName = Struct.new(:name, :formula, :descr) do
            end

            @labels = Array.new
            @names = Array.new

        end

        def get_labels
            @labels.map{|label| label.name}
        end
        def get_names
            @names.map{|name| name.name}
        end
        

        def get_score(name)
            # Evaluate the score in a separate binding context
            b = binding
            #Look up the formula for this scorename
            formula = nil
            finalScore = nil
            @names.each{ |scoreName|
                if scoreName.name == name
                    formula = scoreName.formula
                    break
                end
            }
            if formula
                #Get each component of the formula from their corresponding labels
                $db.transaction { |selfs| 
                    @labels.each { |e| 
                        if formula.match( e[:name] )
                            res = e.prepared_sql.execute!
                            
                            $log.warn("Score-label #{e[:name]} SQL definition returning more than 1 row".yellow) if res.length > 1
                            
                            result = res[0][0] # Row 0 Column 0
                            if result
                                b.local_variable_set(e[:name], result)
                            elsif
                                b.local_variable_set(e[:name],0.0)
                            end
                        end
                    }
                }

                begin
                    score = eval( formula , b ).to_f
                    if !score.nan?
                        finalScore = score
                    else
                        finalScore = 0.0
                    end
                rescue ZeroDivisionError => e
                    $log.warn "Score #{name} formula is invalid #{e.message}".yellow
                end
            
            else
                $log.error "Score #{name} formula not defined"
            end

            return finalScore
        end

        def cleanup

            @labels.each{|label|
                label.prepared_sql.close
            }

        end

    end #end Class
end #End Module
