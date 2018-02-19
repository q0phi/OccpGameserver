module OCCPGameServer

    class NamespaceError < StandardError; end

    #
    # A state value not locate in constants.rb was passed
    #
    class InvalidState < StandardError; end

    #
    # An incorrect value was found in the instance file
    #
    class ParsingError < StandardError; end

end
