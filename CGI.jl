module CGI

    import Base: EnvHash, AsyncStream, Pipe

    # I'm exporting the internal helper functions in case anyone needs to use
    # them in their own app for whatever reason.

    export HttpFormPart, HttpFile, HttpInputCollection,
        CgiResponse, CgiApplication,
        header, CgiParseQuotedParameters, CgiParseHttpParameters,
        CgiPercentDecode, CgiParseSemicolonFields, CgiParseMultipartFormParts,
        CgiStartApplication

    ###
    #   > HttpFormPart (type)
    #
    #       Contains data for a form part sent as multipart/form-data.
    ###

    type HttpFormPart
        headers::Dict{UTF8String, Dict{UTF8String, UTF8String}}
        data::Array{Uint8}

        HttpFormPart() = new (Dict{UTF8String, Dict{UTF8String, UTF8String}}(), Uint8[])
    end

    ###
    #   > HttpFile (type)
    #
    #       Contains information about a file uploaded as multipart/form-data.
    #
    #       > name (field)
    #           The name of the file as reported by the client's machine/browser.
    #       > mime (field)
    #           The MIME type of the file as reported by the client's machine/browser.
    #       > data (field)
    #           Binary file data.
    ###

    type HttpFile
        name::UTF8String
        mime::UTF8String
        data::Array{Uint8}

        HttpFile() = new ("", "", Uint8[])
    end

    ###
    #   > HttpInputCollection (type)
    #
    #       Contains information about the current request/session.
    #
    #       > method (field)
    #           The HTTP request method used to request the page (GET, POST, etc).
    #       > get (field)
    #           An array of string values specified in the URL query string (e.g. ?var=value).
    #       > post (field)
    #           An array of string values sent as form data via POST.
    #       > files (field)
    #           An array of HttpFile objects for files uploaded in the request. 
    ###

    type HttpInputCollection
        method::UTF8String
        get::Dict{UTF8String, UTF8String} # A decision was made here to support only string keys and values
        post::Dict{UTF8String, UTF8String}
        files::Array{HttpFile}

        HttpInputCollection() = new ("", Dict{UTF8String, UTF8String}(), Dict{UTF8String, UTF8String}(), HttpFile[])
    end

    ###
    #   > CgiResponse (type)
    #
    #       Data relevant to the HTTP response to be sent to the client.
    #
    #       > headers (field)
    #           An array of HTTP headers (e.g. Content-Type).
    ###

    type CgiResponse
        headers::Dict{UTF8String, UTF8String}

        CgiResponse() = new (Dict{UTF8String, UTF8String}())
    end

    ###
    #   > CgiApplication (type)
    #
    #       A container for an instance of a CGI application/session.
    #
    #       > input (field)
    #           See HttpInputCollection.
    #       > server (field)
    #           An array of values defined by the environment variables.
    #       > response (field)
    #           The HTTP response to be sent (see CgiResponse).
    #       > stdoutOriginal (field) [internal]
    #           A copy of the handle to the original STDOUT stream.
    #       > outRead (field) [internal]
    #           The read end of the STDOUT pipe created by this module to capture (buffer) output.
    #       > outWrite (field) [internal]
    #           The write end of the STDOUT pipe created by this module to capture (buffer) output.
    ###

    type CgiApplication
        input::HttpInputCollection
        server::Dict{UTF8String, UTF8String}
        response::CgiResponse

        ## Used internally

        stdoutOriginal::AsyncStream
        outRead::Pipe
        outWrite::Pipe

        ##
        
        CgiApplication() = new (HttpInputCollection(), Dict{UTF8String, UTF8String}(), CgiResponse())
    end

    ###
    #   > header (function)
    #
    #       Sets a HTTP header for the given CGI application.
    ###

    function header(app::CgiApplication, field::UTF8String, value::UTF8String)
        app.response.headers[field] = value

        return app
    end

    ###
    #   > CgiParseQuotedParameters (function)
    #
    #       An internal helper function to parse strings in "name=value" format.
    ###

    function CgiParseQuotedParameters(data::UTF8String)
        tokens = split(data, "=", 2)

        if (length(tokens) == 2)
            return (tokens[1], tokens[2])
        end
        
        return null
    end

    ###
    #   > CgiParseHttpParameters (function)
    #
    #       An internal helper function to parse HTTP parameter strings.
    ###

    function CgiParseHttpParameters(dataString::UTF8String)
        tokenArray::Dict{UTF8String, UTF8String} = Dict{UTF8String, UTF8String}()

        if (length(dataString) > 0)
            tokens = split(dataString, "&")

            for token in tokens
                tokenTokens = split(token, "=", 2)

                if (length(tokenTokens) == 2)
                    tokenArray[tokenTokens[1]] = tokenTokens[2]
                else
                    tokenArray[tokenTokens[1]] = ""
                end
            end
        end

        return tokenArray
    end

    ###
    #   > CgiPercentDecode (function)
    #
    #       An internal helper function to decode percent-encoded strings
    #       into UTF-8 strings.
    ###

    function CgiPercentDecode(dataString::UTF8String)
        finalString::UTF8String = ""

        segments = split(dataString, '%', 0, false)

        # If there's more than one segment, there must be a % somewhere that needs decoding.

        if (length(segments) > 1)
            for segment in segments
                # At least two characters are required after the % marker.

                if (length(segment) > 1)
                    # Get the two characters and convert them into their hexadecimal/byte value.

                    try
                        hex = hex2bytes(ascii(segment[1:2]))

                        finalString = string(finalString, utf8(hex))
                    catch error
                        # This will happen if the characters following the % are not valid hexadecimal characters.
                    end

                    # Add the rest of the segment to the byte array.

                    try
                        finalString = string(finalString, segment[3:end])
                    catch error
                        # This will be a bounds error due to the segment being only 2 characters in length.
                        Base.showerror(STDOUT, error)
                    end
                else
                    # Add the segment to the byte array.

                    finalString = string(finalString, segment)
                end
            end # for
        else
            finalString = string(finalString, segments[1])
        end # if

        return finalString
    end

    ###
    #   > CgiPercentDecodeUint8 (function)
    #
    #       An internal helper function to decode percent-encoded strings
    #       into binary data (Uint8).
    ###
    
    function CgiPercentDecodeUint8(dataString::UTF8String)
        data = Uint8[]

        segments = split(dataString, '%', 0, false)

        # If there's more than one segment, there must be a % somewhere that needs decoding.

        if (length(segments) > 1)
            for segment in segments
                # At least two characters are required after the % marker.

                if (length(segment) > 1)
                    # Get the two characters and convert them into their hexadecimal/byte value.

                    try
                        hex = hex2bytes(ascii(segment[1:2]))

                        push!(data, hex[1])
                    catch error
                        # Doesn't matter.
                    end

                    # Add the rest of the segment to the byte array.

                    try
                        append!(data, bytestring(segment[3:end]).data)
                    catch error
                        # Doesn't matter.
                    end
                else
                    # Add the segment to the byte array.

                    append!(data, bytestring(segment).data)
                end
            end # for
        else
            append!(data, bytestring(segments[1]).data)
        end # if

        return data
    end

    ###
    #   > CgiParseSemicolonFields (function)
    #
    #       An internal helper function to parse semicolon-separated data.
    ###
    
    function CgiParseSemicolonFields(dataString::UTF8String)
        dataString = dataString * ";"

        data = Dict{UTF8String, UTF8String}()

        prevCharacter::Char = 0x00
        inSingleQuotes::Bool = false
        inDoubleQuotes::Bool = false
        ignore::Bool = false
        workingString::UTF8String = ""
        
        dataStringLength::Int = length(dataString)
        
        dataStringLengthLoop::Int = dataStringLength + 1
        
        charIndex::Int = 1
        
        while charIndex < dataStringLengthLoop
            character = dataString[charIndex]

            if (!inSingleQuotes && character == '"' && prevCharacter != '\\')
                inDoubleQuotes = !inDoubleQuotes
                ignore = true
            end

            if (!inDoubleQuotes && character == '\'' && prevCharacter != '\\')
                inSingleQuotes = !inSingleQuotes
                ignore = true
            end
            
            if (charIndex == dataStringLength || (character == ';' && !(inSingleQuotes || inDoubleQuotes)))
                workingString = strip(workingString)

                if (length(workingString) > 0)
                    decoded = CgiParseQuotedParameters(workingString)
                
                    if (decoded != null)
                        (key, value) = decoded

                        data[key] = value
                    else
                        data[workingString] = workingString
                    end

                    workingString = ""
                end
            elseif (!ignore)
                workingString = workingString * string(character)
            end
            
            prevCharacter = character
            
            charIndex  = charIndex + 1

            ignore = false
        end

        return data
    end

    ###
    #   > CgiParseMultipartFormParts (function)
    #
    #       An internal helper function to process multipart form data.
    ###

    function CgiParseMultipartFormParts(data::Array{Uint8}, boundary::UTF8String, boundaryLength::Int = length(boundary))
        formParts::Array{HttpFormPart} = HttpFormPart[]

        part::HttpFormPart = HttpFormPart()

        ### Go through each byte of data, parsing it into form parts, headers and data.

        # The loop is perhaps slightly ambitious, as I wanted to be able to parse all the data
        # in one pass - rather than one pass for boundaries, another for headers, etc.

        # According to the spec, the boundary chosen by the client must be a unique string
        # i.e. there should be no conflicts with the data within - so it should be safe to just do a basic string search.

        headerRaw::Array{Uint8} = Uint8[]

        captureAsData::Bool = false

        crOn::Bool = false
        hadLineEnding::Bool = false
        foundBoundary::Bool = false
        foundFinalBoundary::Bool = false

        bytes::Int = length(data)

        byteIndexOffset::Int = 0
        testIndex::Int = 1
        byteTestIndex::Int = 0

        byte::Uint8 = 0x00

        # Skip over the first boundary and CRLF

        byteIndex::Int = boundaryLength + 5

        while (!foundFinalBoundary && byteIndex <= bytes)
            byte = data[byteIndex]

            # Test for boundary.

            if (
                (byte == 0x0d && data[byteIndex + 1] == 0x0a && data[byteIndex + 2] == '-' && data[byteIndex + 3] == '-')
                || (byte == '-' && data[byteIndex + 1] == '-')
            )
                foundBoundary = true

                if (byte == 0x0d)
                    byteIndexOffset = byteIndex + 3
                else
                    byteIndexOffset = byteIndex + 1
                end

                byteTestIndex = byteIndexOffset

                testIndex = 1;

                while (testIndex < boundaryLength)
                    byteTestIndex = byteIndexOffset + testIndex

                    if (byteTestIndex > bytes || data[byteTestIndex] != boundary[testIndex])
                        foundBoundary = false
                        break
                    end

                    testIndex = testIndex + 1
                end

                if (foundBoundary)
                    if (data[byteTestIndex + 2] == '-')
                        foundFinalBoundary = true
                        byteIndex = byteTestIndex + 5
                    else
                        byteIndex = byteTestIndex + 3
                    end

                end
            else
                foundBoundary = false
            end

            ## Otherwise, process data

            if (foundBoundary)
                captureAsData = false
                crOn = false
                hadLineEnding = false
                foundBoundary = false

                push!(formParts, part)

                part = HttpFormPart()
            else
                if (captureAsData)
                    push!(part.data, byte)
                else
                    ## Check for CR

                    if (byte == 0x0d)
                        crOn = true
                    else
                        ## Check for LF and previous CR

                        if (byte == 0x0a && crOn)
                            ## Check for CRLFCRLF

                            if (hadLineEnding)
                                ## End of headers

                                captureAsData = true

                                hadLineEnding = false
                            else
                                ## End of single-line header

                                header::UTF8String = utf8(headerRaw)

                                if (length(header) > 0)
                                    headerParts = split(header, ": ", 2)

                                    valueDecoded = CgiParseSemicolonFields(headerParts[2]);

                                    if (length(valueDecoded) > 0)
                                        part.headers[headerParts[1]] = valueDecoded
                                    end
                                end

                                headerRaw = Uint8[]

                                hadLineEnding = true
                            end
                        else
                            if (hadLineEnding)
                                hadLineEnding = false
                            end

                            push!(headerRaw, byte)
                        end

                        crOn = false
                    end
                end
            end

            byteIndex = byteIndex + 1
        end

        # ...

        return formParts
    end

    ###
    #   > CgiStartApplication (function)
    #
    #       Configure and populate the given CGI application instance.
    ###

    function CgiStartApplication(app::CgiApplication, environment::EnvHash, inputStream::AsyncStream)
        # Save environment variables.
        # Dev note: This loop may not be necessary to ensure that the strings are all UTF-8.

        for (variableName::UTF8String, variableValue::UTF8String) in environment
            app.server[variableName] = variableValue
        end

        # Save the request method

        app.input.method = get!(app.server, "REQUEST_METHOD", "GET")

        ## Parse query string

        app.input.get = CgiParseHttpParameters(app.server["QUERY_STRING"])

        ### Handle POST input (if applicable)

        if (
            app.input.method == "POST"
            && (postDataLength::Int32 = parseint(Int32, get!(app.server, "CONTENT_LENGTH", "0"))) > 0
        )
            # Read data as bytes from the socket.

            postDataBytes::Array{Uint8} = readbytes(inputStream, postDataLength)

            ### Process x-www-form-urlencoded POST data (if applicable)

            if (get!(app.server, "CONTENT_TYPE", "") == "application/x-www-form-urlencoded")
                # Convert POST data to UTF-8 string.

                postDataString::UTF8String = utf8(postDataBytes)

                # Split post data into tokens based on "&" and "=" separators - and then
                # iterate over each token, decoding any percent-encoded data.

                app.input.post = CgiParseHttpParameters(postDataString)

                if (length(app.input.post) > 0)
                    for (name, dataString) in app.input.post
                        app.input.post[name] = CgiPercentDecode(dataString)
                    end
                end

            ### Process multipart/form-data POST data (e.g. file upload/s) (if applicable)

            elseif (searchindex(get!(app.server, "CONTENT_TYPE", ""), "multipart/form-data") != 0)
                boundary::UTF8String = app.server["CONTENT_TYPE"][(searchindex(app.server["CONTENT_TYPE"], "boundary=") + 9):end]

                boundaryLength::Int = length(boundary)

                if (boundaryLength > 0)
                    formParts::Array{HttpFormPart} = CgiParseMultipartFormParts(postDataBytes, boundary, boundaryLength)
                    
                    ### Process form parts

                    if (length(formParts) > 0)
                        for part::HttpFormPart in formParts
                            hasFile::Bool = false
                            file::HttpFile = HttpFile()

                            for (field::UTF8String, values::Dict{UTF8String, UTF8String}) in part.headers
                                if (
                                    field == "Content-Disposition"
                                    && getkey(values, "form-data", null) != null
                                )

                                    # Check to see whether this part is a file upload
                                    # Otherwise, treat as basic POST data

                                    if (getkey(values, "filename", null) != null)
                                        if (length(values["filename"]) > 0)
                                            file.name = values["filename"]
                                            hasFile = true
                                        end
                                    elseif (getkey(values, "name", null) != null)
                                        app.input.post[values["name"]] = utf8(part.data)
                                    end

                                    ## ...
                                elseif (field == "Content-Type")
                                    (file.mime, mime) = first(values)
                                end
                            end # for

                            if (hasFile)
                                file.data = part.data

                                push!(app.input.files, file)

                                file = HttpFile()
                                hasFile = false
                            end # if
                        end # for
                    end # if
                end  # if

            ### ...

            end # if/elseif
        end # End POST

        # ...
        
        return app
    end

    ###
    #   > newApplication (function)
    #
    #       Create an instance of a CGI application.
    ###

    function newApplication(environment::EnvHash = ENV, inputStream::AsyncStream = STDIN)
        # Create instance.

        cgi = CgiApplication()

        # Redirect STDOUT.

        cgi.stdoutOriginal = STDOUT

        (cgi.outRead, cgi.outWrite) = redirect_stdout()

        # Redirect STDERR to STDOUT.

        redirect_stderr(cgi.outWrite)

        ### Standard shutdown routine: write headers and flush output.

        atexit(function ()
            # A content type is required by the CGI spec; if none is set, we'll default to text/html.

            if (getkey(cgi.response.headers, "Content-Type", null) == null)
                cgi.response.headers["Content-Type"] = "text/html"
            end

            # Get buffered output.

            close(cgi.outWrite)

            data = readavailable(cgi.outRead)

            close(cgi.outRead)

            # Restore original STDOUT.

            redirect_stdout(cgi.stdoutOriginal)

            # Output HTTP headers.

            for (header, value) in cgi.response.headers
                print(header * ": " * value * "\r\n")
            end

            print("\r\n")

            # Write output

            print(data)
        end)

        # Boot the default instance

        CgiStartApplication(cgi, environment, inputStream)

        # Return the CGI application instance.

        return cgi
    end
end