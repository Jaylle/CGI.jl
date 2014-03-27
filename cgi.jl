module CGI

## I'm exporting the internal helper functions in case anyone needs to use
## them in their own app for whatever reason.

export HttpFormPart, HttpFile, HttpInputCollection,
    CgiResponse, CgiApplication,
    CgiHeader, CgiParseQuotedParameters, CgiParseHttpParameters,
    CgiPercentDecode, CgiParseSemicolonFields, CgiParseMultipartFormParts,
    CgiStartApplication,
    cgi

## 

type HttpFormPart
    headers::Dict{String, Dict{String, String}}
    data::Array{Uint8}

    HttpFormPart() = new (Dict{String, Dict{String, String}}(), Uint8[])
end

## 

type HttpFile
    name::String
    mime::String
    data::Array{Uint8}

    HttpFile() = new ("", "", Uint8[])
end

## 

type HttpInputCollection
    method::String
    get::Dict{String, String} # A decision was made here to support only string keys and values
    post::Dict{String, String}
    files::Array{HttpFile}

    HttpInputCollection() = new ("", Dict{String, String}(), Dict{String, String}(), HttpFile[])
end

##

type CgiResponse
    headers::Dict{String, String}

    CgiResponse() = new (Dict{String, String}())
end

## 

type CgiApplication
    input::HttpInputCollection
    server::Dict{String, String}
    response::CgiResponse

    ## Used internally

    stdout
    outRead
    outWrite

    ##
    
    CgiApplication() = new (HttpInputCollection(), Dict{String, String}(), CgiResponse())
end

## 

function CgiHeader(field::String, value::String, app::CgiApplication = cgi)
    app.response.headers[field] = value

    return app
end

## Helper function to parse name="value" strings

function CgiParseQuotedParameters(data::String)
    tokens = split(data, "=", 2)

    if (length(tokens) == 2)
        return (tokens[1], tokens[2])
    end
    
    return null
end

## Helper function to parse encoded strings

function CgiParseHttpParameters(data::String)
    tokenArray = Dict{String, String}()

    if (length(data) > 0)
        tokens = split(data, "&")

        for token in tokens
            tokenTokens = split(token, "=", 2)

            if (length(tokenTokens) == 2)
                tokenArray[tokenTokens[1]] = tokenTokens[2]
            end
        end
    end

    return tokenArray
end

## Helper function to decode percent-encoded strings

function CgiPercentDecode(dataString::String)
    data = Uint8[]

    captureEncoding = false
    capturedEncoding = ""

    for character in dataString
        if (character == '%')
            captureEncoding = true
        elseif (captureEncoding)
            capturedEncoding = capturedEncoding * string(character)

            if (length(capturedEncoding) == 2)
                hex = hex2bytes(capturedEncoding)

                push!(data, hex[1])

                captureEncoding = false
                capturedEncoding = ""
            end
        else
            push!(data, uint8(character))
        end
    end

    return data
end

## Helper function to parse semicolon-separated data

function CgiParseSemicolonFields(dataString::String)
    dataString = dataString * ";"

    data = Dict{String, String}()

    prevCharacter = null
    inSingleQuotes = false
    inDoubleQuotes = false
    ignore = false
    workingString = ""
    
    dataStringLength = length(dataString)
    
    dataStringLengthLoop = dataStringLength + 1
    
    charIndex = 1;
    
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

## 

function oldCgiParseMultipartFormPartsOld(data::Array{Uint8}, boundary::String)
    ## Split the form data by its boundary. According to the spec, the boundary chosen
    ## by the client must be a unique string i.e. there should be no conflicts with the
    ## data within - so it should be safe to just do a basic string split.
    
    postDataString = postDataString[1:(rsearchindex(postDataString, "--" * boundary * "--") - 1)]
    
    parts = split(postDataString, "--" * boundary * "\r\n")
    
    if (length(parts) > 0)
        formParts = HttpFormPart[]
    
        for part in parts
            part = part[1:(end - 2)]

            ## Get header for this part

            headerIndex = searchindex(part, "\r\n\r\n")
            
            if (headerIndex > 0)
                headers = Dict{String, Any}()

                headerData = part[1:(headerIndex - 1)]

                for header in split(headerData, "\r\n")
                    if (length(header) > 0)
                        headerParts = split(header, ": ", 2)

                        valueDecoded = CgiParseSemicolonFields(headerParts[2]);

                        if (length(valueDecoded) > 1)
                            headers[headerParts[1]] = valueDecoded
                        else
                            headers[headerParts[1]] = headerParts[2]
                        end

                    end
                end

                ## Get data for this part
                
                push!(formParts, HttpFormPart(headers, part[(headerIndex + 4):end]))
            end
        end
        
        ## Process form parts

        if (length(formParts) > 0)
            for part in formParts
                hasFile = false
                file = HttpFile()

                for (field, values) in part.headers
                    if (
                        field == "Content-Disposition"
                        && isa(values, Dict)
                        && getkey(values, "form-data", null) != null
                    )

                        ## Check to see whether this part is a file upload
                        ## Otherwise, treat as basic POST data

                        if (
                            getkey(values, "filename", null) != null
                            && length(values["filename"]) > 0
                        )
                            file.name = values["filename"]
                            hasFile = true
                        elseif (getkey(values, "name", null) != null)
                            app.input.post[values["name"]] = part.data
                        end

                        ## ...
                    elseif (field == "Content-Type")
                        file.mime = values
                    end
                end

                if (hasFile)
                    file.data = part.data

                    push!(app.input.files, file)

                    file = HttpFile()
                    hasFile = false
                end
            end
        end
    end
end

function CgiParseMultipartFormParts(data::Array{Uint8}, boundary::String, boundaryLength::Int = length(boundary))
    formParts = HttpFormPart[]

    part = HttpFormPart()

    ## Go through each byte of data, parsing it into form parts, headers and data.

    ## The loop is perhaps slightly ambitious, as I wanted to be able to parse all the data in
    ## one pass, rather than one pass for boundaries, another for headers, etc.

    ## According to the spec, the boundary chosen
    ## by the client must be a unique string i.e. there should be no conflicts with the
    ## data within - so it should be safe to just do a basic string search.

    headerRaw = Uint8[]

    captureAsData = false

    crOn = false
    hadLineEnding = false
    foundBoundary = false
    foundFinalBoundary = false

    bytes = length(data)

    byteIndex = boundaryLength + 5 # Skip over the first boundary and CRLF

    while (!foundFinalBoundary && byteIndex <= bytes)
        byte = data[byteIndex]

        ## Test for boundary

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

                            header = utf8(headerRaw)

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

    return formParts
end

## Create a CGI application instance w/ populated data

function CgiStartApplication(environment, inputStream, app = CgiApplication())
    ## Load environment variables

    for (field, val) in environment
        app.server[field] = val
    end

    ## Get request method

    if (getkey(app.server, "REQUEST_METHOD", null) != null)
        app.input.method = app.server["REQUEST_METHOD"]
    else
        app.input.method = "GET"
    end

    ## Parse query string

    app.input.get = CgiParseHttpParameters(app.server["QUERY_STRING"])

    ## Process x-www-form-urlencoded POST data (if applicable)

    if (
        app.input.method == "POST"
        && getkey(app.server, "CONTENT_TYPE", null) != null
        && app.server["CONTENT_TYPE"] == "application/x-www-form-urlencoded"
        && getkey(app.server, "CONTENT_LENGTH", null) != null
    )
        charLength = int(app.server["CONTENT_LENGTH"])

        if (charLength > 0)
            p = readbytes(inputStream, charLength)

            postDataString = utf8(p)

            if (length(postDataString) > 0)
                ## Split post data into tokens based on "&" and "=" separators - and 
                ## then iterate over each token, decoding any percent-encoded data.

                app.input.post = CgiParseHttpParameters(postDataString)

                if (length(app.input.post) > 0)
                    for (name, dataString) in app.input.post
                        app.input.post[name] = CgiPercentDecode(dataString)
                    end
                end
            end
        end
    end
    
    ## Process multipart/form-data POST data (if applicable)

    if (
        app.input.method == "POST"
        && getkey(app.server, "CONTENT_TYPE", null) != null
        && searchindex(app.server["CONTENT_TYPE"], "multipart/form-data") != 0
        && getkey(app.server, "CONTENT_LENGTH", null) != null
    )
        charLength = int(app.server["CONTENT_LENGTH"])

        if (charLength > 0)
            boundary = app.server["CONTENT_TYPE"][(searchindex(app.server["CONTENT_TYPE"], "boundary=") + 9):end]

            boundaryLength = length(boundary)

            if (boundaryLength > 0)
                formParts = CgiParseMultipartFormParts(readbytes(inputStream, charLength), boundary, boundaryLength)
                
                ## Process form parts

                if (length(formParts) > 0)
                    for part in formParts
                        hasFile = false
                        file = HttpFile()

                        for (field, values) in part.headers
                            if (
                                field == "Content-Disposition"
                                && isa(values, Dict)
                                && getkey(values, "form-data", null) != null
                            )

                                ## Check to see whether this part is a file upload
                                ## Otherwise, treat as basic POST data

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
                        end

                        if (hasFile)
                            file.data = part.data

                            push!(app.input.files, file)

                            file = HttpFile()
                            hasFile = false
                        end
                    end
                end
            end
        end
    end

    ## 
    
    return app
end

####################################################

function CgiHeader(field::String, value::String, app::CgiApplication = cgi)
    app.response.headers[field] = value

    return app
end

####################################################

## Create a default instance of the CGI application

cgi = CgiApplication()

## Redirect STDOUT

cgi.stdout = STDOUT

(cgi.outRead, cgi.outWrite) = redirect_stdout()

## Redirect STDERR to STDOUT

redirect_stderr(cgi.outWrite)

## Standard shutdown routine:
## Write headers and flush output

atexit(function ()
    ## A content type is required by the CGI spec; if none is set, we'll default to text/html.

    if (getkey(cgi.response.headers, "Content-Type", null) == null)
        cgi.response.headers["Content-Type"] = "text/html"
    end

    ## Get buffered output

    close(cgi.outWrite)

    data = readavailable(cgi.outRead)

    close(cgi.outRead)

    ## Restore STDOUT

    redirect_stdout(cgi.stdout)

    ## Output headers 

    for (header, value) in cgi.response.headers
        print(header * ": " * value * "\r\n")
    end

    print("\r\n")

    ## Write output

    print(data)
end)

## Boot the default instance

CgiStartApplication(ENV, STDIN, cgi)

close(STDIN)

########################################################

end