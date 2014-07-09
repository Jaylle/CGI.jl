# Julia CGI

### Background

I have been assessing the potential for using Julia in web development. This module was developed so that Julia may be used in a Fast/CGI environment.

The module currently provides a basic API for sending output and HTTP headers. Query strings, POST data and file uploads (multipart form data) are all supported.

Development and testing has been done on:

* CentOS 6.5 64-bit under nginx with FastCGI.
* Windows 7 64-bit under Apache with mod_cgi.

#### Important note:

 In its current state, the various parsers within the module are rudimentary; a specially-crafted HTTP request could potentially cause a bounds error. This shouldn't pose a significant security risk by itself, but may cause harm depending on the specifics of your application and the execution environment.

### Usage

#### Installation

To use this module, place the CGI.jl file <a href="http://julia.readthedocs.org/en/latest/manual/modules/#module-paths" target="_blank">somewhere that Julia will be able to find it</a>. Within your Julia code, add the line

    using CGI

#### Creating a CGI instance

*Important change since version 0.1: The module no longer automatically creates an instance for you; you must now do this manually.*

To create a new instance, call the module's **`newApplication`** method. This method returns an object of the type **`CgiApplication`**. For example:

    using CGI

    app = CGI.newApplication()

Below is a list of relevant types and their properties:

* **`CgiApplication`**

 * **`input::HttpInputCollection` :** GET, POST and file data.
 * **`server::Dict{UTF8String, UTF8String}` :** Environment variables.
 * **`response::CgiResponse` :** The response object (headers).

* **`HttpInputCollection`**

 * **`method::UTF8String` :** The HTTP method sent in the request (e.g. GET or POST).
 * **`get::Dict{UTF8String, UTF8String}` :** The query values passed in the URL (e.g. ?var=value).
 * **`post::Dict{UTF8String, UTF8String}` :** POST data.
 * **`files::Array{HttpFile}` :** Uploaded files.

* **`CgiResponse`**

 * **`headers::Dict{UTF8String, UTF8String}` :** The HTTP headers to be sent in the response.

#### Sending headers

To set HTTP headers to be sent with the response, the module provides the API function

**`header(app::CgiApplication, field::String, value::String | value::Int)`**.

The function can be called as either **`header`** or **`CGI.header`** e.g:

	header(app, "Test-Http-Header", "1")
	CGI.header(app, "Test-Http-Header-2", 2)

In normal operation, headers can be set at any point in the application i.e. it's not a requirement that headers be set before any data is output *(due to output buffering; see below)*.

#### Writing output

Output can be written using the standard Julia output functions. The CGI module will create an output buffer to store all output. The contents of the buffer will be flushed **as soon as the module's atexit hook is called** e.g. when the program finishes execution or one of the **`quit`**/**`exit`** functions are called.

#### Working with input

GET, POST and file data can be accessed through the **`HttpInputCollection`**'s **`get`**, **`post`** and **`files`** fields respectively.

##### Query strings

GET query values are stored in a **`Dict{UTF8String, UTF8String}`**.

Below is an example of how to access data from the GET array:

    print("Hello, " * app.input.get["name"])

##### POST data

POST data is stored in a **`Dict{UTF8String, UTF8String}`**.

Below is an example of how to access data from the POST array:

    print("Hello, " * app.input.post["name"])

##### File data

File data is stored in a string-indexed **`Dict`** of **`HttpFile`** objects.

**`HttpFile`** has the following properties:

* **`name::String` :** The original name of the file, as reported by the browser.
* **`mime::String` :** The MIME type of the file, as reported by the browser.
* **`data::Array{Uint8}` :** The file data, stored in raw binary form as a byte array.

The below example demonstrates how to save an uploaded file.

    if (length(app.input.files) > 0)
        ffile = app.input.files["picture"]
        fcopy = open(ffile.name, "w+")
        write(fcopy, ffile.data)
        close(fcopy)
    end

### Internals / behaviour

This module will redirect STDOUT to a new pipe. This is so that calls to the print function don't cause erroneous CGI responses if the headers haven't been output.

STDERR is redirected to STDOUT so that errors are written to the output buffer and don't cause the web server to hang.

A function is registered using **`atexit`** to grab the contents of the output buffer, restore the original STDOUT and write any headers and output.

### Development

**Requests, suggestions and bug reports always welcome.**

#### Known issues

* Lax input sanitation.
* No error checking for invalid UTF-8 strings *(this is not confirmed as a real issue, but I suspect it may have the potential to cause problems)*.

#### Planned improvements

* Support for cookies.
* Ability to manipulate the output buffer (e.g. retrieve contents, flush, clean).
* A convenient method of redrecting errors to a log file instead of writing to STDOUT. (This can obviously be done in user code by leveraging **`redirect_stderr`**)


