import ipairs, type from _G
import popen from io
import match from string
import concat, insert from table

import readdirSync, statSync from require "fs"
import join from require "path"
import nextTick from process

-- ::PATHS_TO_WATCH -> table
-- Represents the filesystem paths designated for watching for modifications
--
PATHS_TO_WATCH = {}

-- ::scanTimestamps(string directory) -> number
-- Retrieves the most recent modification timestamp from files in the directory
--
scanTimestamps = (directory) ->
    lastModified    = -1
    files           = collectFiles(directory)

    -- Retrieve the most recent modification timestamp
    local modificationTime
    for file in *files
        modificationTime    = statSync(join(directory, file)).mtime.sec
        lastModified        = modificationTime if lastModified < modificationTime

    return lastModified

-- ::watchLoop() -> void
-- Checks designated filesystem paths for modifications
--
local watchLoop
watchLoop = () ->
    -- Eject any filesystem paths that since have been removed or otherwise
    PATHS_TO_WATCH = [entry for entry in *PATHS_TO_WATCH when isDir(entry.path) or isFile(entry.path)]

    local lastModified
    for entry in *PATHS_TO_WATCH
        if isDir(entry.path) then lastModified  = scanTimestamps(entry.path)
        else lastModified                       = statSync(entry.path).mtime.sec

        -- If the filesystem path has not been initialize yet, reset timestamp
        if entry.lastModified == -1 then entry.lastModified = lastModified
        elseif entry.lastModified ~= lastModified
            -- If the previous timestamp does not match, update and dispatch callback
            entry.callback(entry.path)
            entry.lastModified = lastModified

    nextTick(watchLoop) if #PATHS_TO_WATCH > 0

-- ::collectFiles(string path, table paths?, string base?) -> table
--
-- export
export collectFiles = (path, paths={}, base="") ->
    error("bad argument #1 to 'collectFiles' (expected string)") unless type(path) == "string"
    error("bad argument #1 to 'collectFiles' (invalid path)") unless isDir(path) or isFile(path)
    error("bad argument #2 to 'collectFiles' (expected table)") unless type(paths) == "table"
    error("bad argument #3 to 'collectFiles' (expected string)") unless type(base) == "string"

    local joined
    for name in *readdirSync(path)
        joined = join(path, name)

        -- If the path is a file, append it, otherwise recursively scan for more files
        if isFile(joined) then insert(paths, join(base, name))
        else collectFiles(joined, paths, join(base, name))

    return paths

-- ::formatCommand(string ...) -> string
-- Formats the string vararg provided into a proper command string, quoting any arguments with spaces
-- export
export formatCommand = (...) ->
    -- Convert the vararg into a table then process the arguments
    commandArguments = {...}
    for index, commandArgument in ipairs(commandArguments)
        -- Wrap the string in quotations if it has a spacing character
        commandArguments[index] = "'#{commandArgument}'" if match(commandArgument, "%s")

    -- Return concatenate the command arguments by space
    return concat(commandArguments, " ")

-- ::exec(string command) -> boolean, number or nil, string or nil
-- Executes the command, returning the status code and stdout
-- export
export exec = (command) ->
    -- Open the process and return the output
    -- NOTE: Luvit is compiled to return the sigterm and status with io.popen
    handle              = popen(command, "r")
    stdout              = handle\read("*a")
    success, _, status  = handle\close()
    return success, status, stdout

-- ::execFormat(string ...) -> boolean, number or nil, string or nil
-- Executes the command, formatting the arguments together, returning the status code and stdout
-- export
export execFormat = (...) ->
    -- Format the arguments and execute the command
    return exec(formatCommand(...))

-- ::isDir(string path) -> boolean
-- Returns if the path is a directory
-- export
export isDir = (path) ->
    fileStats = statSync(path)
    return fileStats and fileStats.type == "directory" or false

-- ::isFile(string path) -> boolean
-- Returns if the path is a file
-- export
export isFile = (path) ->

    fileStats = statSync(path)
    return fileStats and fileStats.type == "file" or false

-- ::watchPath(string path, function callback) -> void
-- Watches the specified path for changes
-- export
export watchPath = (path, callback) ->
    error("bad argument #1 to 'watchPath' (expected string)") unless type(path) == "string"
    error("bad argument #1 to 'watchPath' (invalid path)") unless isDir(path) or isFile(path)
    error("bad argument #2 to 'watchPath' (expected function)") unless type(callback) == "function"

    insert(PATHS_TO_WATCH, {
        callback:       callback
        path:           path
        lastModified:   -1
    })

    if #PATHS_TO_WATCH == 1 then nextTick(watchLoop)