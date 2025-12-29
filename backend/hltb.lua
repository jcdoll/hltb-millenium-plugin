--[[
    HLTB API Client for Lua

    Standalone module for querying HowLongToBeat.com
    Requires: http, json, logger modules

    API implementation based on:
    https://github.com/ScrappyCocco/HowLongToBeat-PythonAPI

    Usage:
        local hltb = require("hltb")
        local game_data = hltb.search_best_match("Dark Souls", steam_app_id)
        if game_data then
            print(game_data.game_name, game_data.comp_main)
        end
]]

local http = require("http")
local json = require("json")
local logger = require("logger")
local utils = require("hltb_utils")

local M = {}

M.BASE_URL = "https://howlongtobeat.com/"
M.REFERER_HEADER = M.BASE_URL
M.TIMEOUT = 60
M.TOKEN_TTL = 300
M.SEARCH_SIZE = 20
-- Static fallback URL
M.SEARCH_URL = M.BASE_URL .. "api/search"

-- Cache
local cached_token = nil
local cached_search_url = nil
local cached_build_id = nil
local cached_homepage = nil
local token_expires_at = 0

-- User agent for requests
local USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

-- Known non-search API endpoints to skip
local SKIP_ENDPOINTS = {
    find = true,
    error = true,
    user = true,
    logout = true
}

-- Validate that a table has required fields with expected types
-- Returns true if valid, or false and the failing field name
local function validate_fields(tbl, schema)
    for _, field in ipairs(schema) do
        if type(tbl[field.name]) ~= field.expected_type then
            return false, field.name
        end
    end
    return true, nil
end

-- Fetch and cache the HLTB homepage (used by multiple extraction functions)
local function get_homepage()
    if cached_homepage then
        return cached_homepage
    end

    logger:info("Fetching HLTB homepage...")

    local headers = {
        ["User-Agent"] = USER_AGENT,
        ["referer"] = M.REFERER_HEADER
    }

    local response, err = http.get(M.BASE_URL, {
        headers = headers,
        timeout = M.TIMEOUT
    })

    if not response or response.status ~= 200 then
        logger:info("Failed to fetch homepage")
        return nil
    end

    cached_homepage = response.body
    return cached_homepage
end

-- Extract search endpoint from website JavaScript
-- Searches all NextJS chunk scripts for fetch POST calls to /api/*
local function extract_search_url()
    logger:info("Extracting search endpoint from website...")

    local homepage = get_homepage()
    if not homepage then
        return nil
    end

    local headers = {
        ["User-Agent"] = USER_AGENT,
        ["referer"] = M.REFERER_HEADER
    }

    -- Find all chunk scripts: _next/static/chunks/*.js
    local script_urls = {}
    for src in homepage:gmatch('["\'](/_next/static/chunks/[^"\']+%.js)["\']') do
        table.insert(script_urls, src)
    end

    logger:info("Found " .. #script_urls .. " chunk script(s)")

    -- Check each script for POST fetch to /api/*
    local endpoints_found = {}
    for _, script_src in ipairs(script_urls) do
        local script_url = M.BASE_URL .. script_src:sub(2) -- remove leading /

        local script_resp = http.get(script_url, {
            headers = headers,
            timeout = M.TIMEOUT
        })

        if script_resp and script_resp.status == 200 and script_resp.body then
            local content = script_resp.body

            -- Look for: "/api/xxx" with POST nearby
            -- Pattern: fetch("/api/endpoint",{...method:"POST"...})
            for api_path in content:gmatch('["\'](/api/[a-zA-Z0-9_]+)["\']') do
                local endpoint = api_path:match('/api/([a-zA-Z0-9_]+)')

                if endpoint and not endpoints_found[endpoint] then
                    endpoints_found[endpoint] = true

                    if SKIP_ENDPOINTS[endpoint] then
                        logger:info("Skipping endpoint: /api/" .. endpoint)
                    else
                        -- Verify it's used with POST method
                        local pattern = 'fetch%s*%(%s*["\']' .. api_path:gsub('/', '%%/') .. '["\']%s*,%s*{[^}]-method%s*:%s*["\']POST["\']'
                        if content:find(pattern) then
                            logger:info("Found search endpoint: /api/" .. endpoint)
                            return "api/" .. endpoint
                        else
                            logger:info("Endpoint /api/" .. endpoint .. " not used with POST")
                        end
                    end
                end
            end
        end
    end

    logger:info("No valid search endpoint found in " .. #script_urls .. " scripts")
    return nil
end

-- Extract NextJS build ID from homepage (for game data requests)
local function extract_build_id()
    if cached_build_id then
        return cached_build_id
    end

    logger:info("Extracting NextJS build ID...")

    local homepage = get_homepage()
    if not homepage then
        return nil
    end

    -- Look for /_next/static/{buildId}/_ssgManifest.js or _buildManifest.js
    local build_id = homepage:match('/_next/static/([^/]+)/_ssgManifest%.js')
    if not build_id then
        build_id = homepage:match('/_next/static/([^/]+)/_buildManifest%.js')
    end

    if build_id then
        logger:info("Found NextJS build ID: " .. build_id)
        cached_build_id = build_id
        return build_id
    end

    logger:info("Could not find NextJS build ID")
    return nil
end

-- Fetch game data by game ID (returns completion times)
-- Matches reference: fetchGameData
local function fetch_game_data(game_id)
    local build_id = extract_build_id()
    if not build_id then
        return nil
    end

    local url = M.BASE_URL .. "_next/data/" .. build_id .. "/game/" .. game_id .. ".json"
    logger:info("Fetching game data: " .. url)

    local headers = {
        ["User-Agent"] = USER_AGENT,
        ["referer"] = M.REFERER_HEADER
    }

    local response, err = http.get(url, {
        headers = headers,
        timeout = M.TIMEOUT
    })

    if not response then
        logger:info("Game data request failed: " .. (err or "unknown"))
        return nil
    end

    if response.status ~= 200 then
        logger:info("Game data request returned HTTP " .. response.status)
        return nil
    end

    local success, data = pcall(json.decode, response.body)
    if not success or not data then
        logger:info("Invalid JSON response for game data")
        return nil
    end

    -- Validate structure: pageProps.game.data.game must be array
    if type(data.pageProps) ~= "table" then
        logger:info("Unexpected JSON data for game page: no pageProps")
        return nil
    end

    if type(data.pageProps.game) ~= "table" then
        logger:info("Unexpected JSON data for game page: no game")
        return nil
    end

    if type(data.pageProps.game.data) ~= "table" then
        logger:info("Unexpected JSON data for game page: no data")
        return nil
    end

    local game_array = data.pageProps.game.data.game
    if type(game_array) ~= "table" then
        logger:info("Unexpected JSON data for game page: game is not array")
        return nil
    end

    -- Reference: gameDataList.length !== 1
    if #game_array ~= 1 then
        logger:info("Unexpected JSON data for game page: game array length is " .. #game_array)
        return nil
    end

    local game_data = game_array[1]

    -- Validate all required fields (matching reference exactly)
    local valid, failed_field = validate_fields(game_data, {
        { name = "comp_main", expected_type = "number" },
        { name = "comp_plus", expected_type = "number" },
        { name = "comp_100", expected_type = "number" },
        { name = "comp_all", expected_type = "number" },
        { name = "game_id", expected_type = "number" },
        { name = "profile_steam", expected_type = "number" },
        { name = "game_name", expected_type = "string" },
    })
    if not valid then
        logger:info("Unexpected JSON data: " .. failed_field .. " has wrong type")
        return nil
    end

    return game_data
end

-- Get search URL with fallback logic
local function get_search_url()
    if cached_search_url then
        return cached_search_url
    end

    -- Try to extract from _app- scripts
    local search_url = extract_search_url()

    if search_url then
        cached_search_url = M.BASE_URL .. search_url
        logger:info("Search URL: " .. cached_search_url)
    else
        cached_search_url = M.SEARCH_URL
        logger:info("Using fallback search URL: " .. cached_search_url)
    end

    return cached_search_url
end

-- Get auth token (matches Python: send_website_get_auth_token)
function M.get_auth_token(force_refresh)
    local now = os.time()

    if not force_refresh and cached_token and now < token_expires_at then
        return cached_token, nil
    end

    logger:info("Fetching auth token...")

    -- Matches Python: get_auth_token_request_params()
    local timestamp_ms = math.floor(now * 1000)
    local url = M.BASE_URL .. "api/search/init?t=" .. timestamp_ms

    -- Matches Python: get_title_request_headers()
    local response, err = http.get(url, {
        headers = {
            ["User-Agent"] = USER_AGENT,
            ["referer"] = M.REFERER_HEADER
        },
        timeout = M.TIMEOUT
    })

    if not response then
        return nil, "Request failed: " .. (err or "unknown")
    end

    if response.status ~= 200 then
        return nil, "HTTP " .. response.status
    end

    local success, data = pcall(json.decode, response.body)
    if not success or not data then
        return nil, "Invalid JSON response"
    end

    if not data.token then
        return nil, "No token in response"
    end

    cached_token = data.token
    token_expires_at = now + M.TOKEN_TTL
    logger:info("Got auth token")

    return data.token, nil
end

-- Build search payload (matches Python: get_search_request_data EXACTLY)
local function get_search_request_data(game_name, modifier, page)
    modifier = modifier or ""
    page = page or 1

    -- Split game name into search terms (matches Python: game_name.split())
    local search_terms = {}
    for word in game_name:gmatch("%S+") do
        table.insert(search_terms, word)
    end

    -- Matches Python payload EXACTLY
    local payload = {
        searchType = "games",
        searchTerms = search_terms,
        searchPage = page,
        size = M.SEARCH_SIZE,
        searchOptions = {
            games = {
                userId = 0,
                platform = "",
                sortCategory = "popular",
                rangeCategory = "main",
                rangeTime = {
                    min = 0,
                    max = 0
                },
                gameplay = {
                    perspective = "",
                    flow = "",
                    genre = "",
                    difficulty = ""
                },
                rangeYear = {
                    max = "",
                    min = ""
                },
                modifier = modifier
            },
            users = {
                sortCategory = "postcount"
            },
            lists = {
                sortCategory = "follows"
            },
            filter = "",
            sort = 0,
            randomizer = 0
        },
        useCache = true
    }

    return json.encode(payload)
end

-- Build search headers (matches hltb-for-deck)
local function get_search_request_headers(auth_token)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Origin"] = "https://howlongtobeat.com",
        ["Referer"] = "https://howlongtobeat.com/",
        ["Authority"] = "howlongtobeat.com",
        ["User-Agent"] = USER_AGENT
    }

    if auth_token then
        headers["x-auth-token"] = auth_token
    end

    return headers
end

-- Search HLTB (matches reference: fetchSearchResults)
function M.search(query, options)
    options = options or {}
    local page = options.page or 1
    local modifier = options.modifier or ""

    -- Get auth token
    local auth_token = M.get_auth_token()
    if not auth_token then
        logger:info("Failed to get auth token")
        return nil
    end

    -- Get headers
    local headers = get_search_request_headers(auth_token)

    -- Get search URL (with extraction logic)
    local search_url = get_search_url()

    -- Get payload
    local payload = get_search_request_data(query, modifier, page)

    -- Make request
    local response, err = http.request(search_url, {
        method = "POST",
        headers = headers,
        data = payload,
        timeout = M.TIMEOUT
    })

    if not response then
        logger:info("Search request failed: " .. (err or "unknown"))
        return nil
    end

    if response.status ~= 200 then
        logger:info("Search returned HTTP " .. response.status)
        return nil
    end

    local success, data = pcall(json.decode, response.body)
    if not success or not data then
        logger:info("Invalid JSON response for search")
        return nil
    end

    -- Validate results array (matching reference: fetchSearchResults)
    if type(data.data) ~= "table" then
        logger:info("Unexpected JSON data for search results: data is not array")
        return nil
    end

    -- Log first result to see all available fields
    if #data.data > 0 then
        local first = data.data[1]
        local fields = {}
        for k, v in pairs(first) do
            table.insert(fields, k .. "=" .. tostring(v))
        end
        table.sort(fields)
        logger:info("Search result fields: " .. table.concat(fields, ", "))
    end

    -- Validate each item has required fields
    for _, item in ipairs(data.data) do
        if type(item.game_id) ~= "number" then
            logger:info("Unexpected JSON data for search results: game_id is not number")
            return nil
        end
        if type(item.game_name) ~= "string" then
            logger:info("Unexpected JSON data for search results: game_name is not string")
            return nil
        end
        if type(item.comp_all_count) ~= "number" then
            logger:info("Unexpected JSON data for search results: comp_all_count is not number")
            return nil
        end
    end

    return data
end

-- Find most compatible game data (matches reference: fetchMostCompatibleGameData)
function M.search_best_match(app_name, steam_app_id)
    logger:info("Searching HLTB for: " .. app_name)

    local search_results = M.search(app_name)
    if not search_results then
        return nil
    end

    if #search_results.data == 0 then
        logger:info("No search results found for: " .. app_name)
        return nil
    end

    logger:info("Found " .. #search_results.data .. " search results")

    -- Search results already contain completion times, so we can return them directly
    -- Only fetch_game_data is needed for Steam ID verification (profile_steam field)

    -- Check exact name match first (no HTTP needed)
    local normalized_app_name = utils.sanitize_game_name(app_name):lower()
    for _, item in ipairs(search_results.data) do
        if utils.sanitize_game_name(item.game_name):lower() == normalized_app_name then
            logger:info("Found exact name match: " .. item.game_name)
            return item
        end
    end

    -- Find closest match using Levenshtein distance
    local possible_choices = {}
    for _, item in ipairs(search_results.data) do
        local normalized_item_name = utils.sanitize_game_name(item.game_name):lower()
        local distance = utils.levenshtein_distance(normalized_app_name, normalized_item_name)
        table.insert(possible_choices, {
            distance = distance,
            comp_all_count = item.comp_all_count,
            item = item
        })
    end

    -- Sort by distance, then by comp_all_count descending
    table.sort(possible_choices, function(a, b)
        if a.distance == b.distance then
            return a.comp_all_count > b.comp_all_count
        end
        return a.distance < b.distance
    end)

    -- Try Steam ID match on top candidates (requires HTTP to get profile_steam)
    if steam_app_id and #possible_choices > 0 then
        local max_steam_id_checks = 3
        for i = 1, math.min(max_steam_id_checks, #possible_choices) do
            local candidate = possible_choices[i]
            local game_data = fetch_game_data(candidate.item.game_id)
            if game_data and game_data.profile_steam == steam_app_id then
                logger:info("Found match by Steam ID: " .. candidate.item.game_name)
                return candidate.item
            end
        end
    end

    -- Return best Levenshtein match
    if #possible_choices > 0 then
        local best = possible_choices[1]
        logger:info("Found closest match: " .. best.item.game_name .. " (distance: " .. best.distance .. ")")
        return best.item
    end

    return nil
end

-- Clear cached values (for retry on 404/stale data)
function M.clear_cache()
    cached_search_url = nil
    cached_build_id = nil
    cached_homepage = nil
    cached_token = nil
    token_expires_at = 0
end

return M
