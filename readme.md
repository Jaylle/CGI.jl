# Julia CGI

### Background

I have been assessing the potential for using Julia in web development. This module is the result of my need to access data sent to the web server whilst running Julia using Apache and mod_cgi.

The module was developed and tested only on the prerelease of Julia 0.3, due to version 0.2's bizarre I/O quirks (on Windows, at least).

Read more about running Julia under Apache and the complications with Julia version 0.2 at [http://thenewphalls.wordpress.com/2014/02/15/julia-and-apache/](http://thenewphalls.wordpress.com/2014/02/15/julia-and-apache/)

#### tl;dr

This module currently supports query strings, POST data and file uploads (i.e. multipart form data).

#### Important note:

 In its current state, the various parsers within the module are rudimentary and a specially-crafted HTTP request could potentially cause a bounds error.

### Usage

To include the module, add the line

    use CGI

to the beginning of your file.

The CGI module will automatically create a `cgi` variable for an instance of the CgiApplication object, which has the following properties:

* **input::HttpInputCollection**: GET, POST and file data
* **server::Dict{String, String}**: Environment variables
* **response::CgiResponse**: The response object (headers).

### Behaviour

The module will redirect STDOUT to a new pipe, for which the handles are stored in the CgiApplication object (`cgi`). This is so that calls to the print function don't cause erroneous CGI responses if the headers haven't been output.

STDERR is redirected to STDOUT so that errors are written to the output buffer and don't cause the web server to hang. Read more about this at [http://thenewphalls.wordpress.com/2014/03/21/capturing-output-in-julia/](http://thenewphalls.wordpress.com/2014/03/21/capturing-output-in-julia/)

A function is registered using atexit() to grab the contents of the output buffer, restore the original STDOUT and write any headers and output.

### Accessing input

GET, POST and file data can be accessed through `cgi.input.get`, `cgi.input.post` and `cgi.input.files` respectively.

#### Query strings

GET data is stored in a Dict{String, String}.

Below is an example of how to access data from the GET array:

    print("Hello, " * cgi.input.get["name"])

#### POST data

POST data is stored in a Dict{String, String}.

Below is an example of how to access data from the POST array:

    print("Hello, " * cgi.input.post["name"])

#### File data

File data is stored in an instance of HttpFile, which has the following properties:

* **name::String**: The field name (e.g. &lt;input type="file" name="**upload**">
* **mime::String**: The MIME type of the file, as reported by the browser.
* **data::Array{Uint8}**: The file data, stored as a byte array.

The below example saves a copy of a submitted file, demonstrating how to access data within the HttpFile object.

    if (length(cgi.input.files) > 0)
        ffile = first(cgi.input.files)
        fcopy = open(ffile.name, "w+")
        write(fcopy, ffile.data)
        close(fcopy)
    end