module OCCPGameServer

    class NamespaceError < StandardError; end

    #
    # A state value not locate in constants.rb was passed
    #
    class InvalidState < StandardError; end
end
