module OCCPGameServer

    # This class handles all of the score calculations and what-nots
    class Score

        attr_accessor :labels, :names, :ScoreLabel, :ScoreName
        def initialize

            @ScoreLabel = Struct.new(:name, :select, :where, :calculation) do

                def get_sql
                    sql = "SELECT SUM(value) FROM SCORE WHERE groupname='#{name}'"
                    if not select.nil?
                        sql = "SELECT #{select} FROM SCORE"
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
                def get_score

                    return 1
                end


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
            
            #Look up the formula for this scorename
            formula = nil
            @names.each{ |scoreName|
                if scoreName.name == name
                    formula = scoreName.formula
                    break
                end
            }
            if formula
                #Get each component of the formula from their corresponding labels

                #Convert the formula from a string into its component parts
                $db.transaction { |selfs| 
                    @labels.each { |e| 
                        if formula.match( e[:name] )
                            result = $db.get_first_value(e.get_sql)
                            if result
                                formula = formula.gsub(e[:name], result.to_s)
                            elsif
                                formula = formula.gsub(e[:name], 0.to_s)
                            end
                        end
                    }
                }

                score = eval(formula)
                return score
            end
            nil
        end

    end #end Class
end #End Module
