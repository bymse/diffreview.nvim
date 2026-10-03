local categories = {
  unit = true,
  integration = true,
  functional = true,
}

local accepted_categories = 'unit, integration, functional'

local function configuration_error(message)
  error('Test configuration error: ' .. message, 0)
end

local function load_module(module_name)
  local loaded, module_or_error = pcall(require, module_name)
  if not loaded then
    configuration_error(string.format('could not load %q:\n%s', module_name, module_or_error))
  end

  return module_or_error
end

local function validate_registry(category, registry)
  if type(registry) ~= 'table' then
    configuration_error(string.format('registry %q must return an array of module names', category))
  end

  local count = 0
  for index, module_name in pairs(registry) do
    if type(index) ~= 'number' or index < 1 or index % 1 ~= 0 then
      configuration_error(string.format('registry %q must be an array of module names', category))
    end

    if type(module_name) ~= 'string' or module_name == '' then
      configuration_error(string.format('registry %q contains an invalid module name', category))
    end

    count = count + 1
  end

  if count == 0 then
    configuration_error(string.format('registry %q must not be empty', category))
  end

  for index = 1, count do
    if registry[index] == nil then
      configuration_error(string.format('registry %q must be an array of module names', category))
    end
  end
end

local function collect_tests(category)
  local registry = load_module(category)
  validate_registry(category, registry)

  local tests = {}
  local test_names = {}

  for _, module_name in ipairs(registry) do
    local test_module = load_module(module_name)
    if type(test_module) ~= 'table' then
      configuration_error(string.format('test module %q must return a table of test functions', module_name))
    end

    for test_name, test in pairs(test_module) do
      if type(test_name) ~= 'string' or test_name == '' then
        configuration_error(string.format('test module %q contains an invalid test name', module_name))
      end

      if type(test) ~= 'function' then
        configuration_error(string.format('test %q in module %q must be a function', test_name, module_name))
      end

      if tests[test_name] then
        configuration_error(string.format('duplicate test name %q', test_name))
      end

      tests[test_name] = test
      table.insert(test_names, test_name)
    end
  end

  table.sort(test_names)
  return tests, test_names
end

local function parse_arguments()
  if #arg < 1 or #arg > 2 or not categories[arg[1]] then
    error('Expected a category and optional exact test name. Categories: ' .. accepted_categories, 0)
  end

  local test_name = arg[2]
  if test_name == '' then
    return arg[1], nil
  end

  return arg[1], test_name
end

local category, requested_test_name = parse_arguments()
local tests, test_names = collect_tests(category)
if requested_test_name then
  if not tests[requested_test_name] then
    configuration_error(string.format('test %q was not found in category %q', requested_test_name, category))
  end

  test_names = { requested_test_name }
end
local failures = {}
local TEST_TIMEOUT_MS = 10000

---@param test fun()
---@return boolean passed
---@return string|nil traceback
local function run_test(test)
  ---@type boolean, string|nil
  local passed, traceback = false, nil

  local co = coroutine.create(function()
    local ok, err = xpcall(test, debug.traceback)
    passed = ok
    traceback = err
  end)

  local resumed, resume_error = coroutine.resume(co)
  if not resumed then
    return false, resume_error
  end

  if coroutine.status(co) ~= 'dead' then
    local completed = vim.wait(TEST_TIMEOUT_MS, function()
      return coroutine.status(co) == 'dead'
    end, 10)

    if not completed then
      return false, 'test did not complete within ' .. TEST_TIMEOUT_MS .. ' ms'
    end
  end

  return passed, traceback
end

local passed_count = 0

for _, test_name in ipairs(test_names) do
  local passed, traceback = run_test(tests[test_name])
  if passed then
    passed_count = passed_count + 1
  else
    print(string.format('FAIL %s:%s\n%s', category, test_name, traceback))
    table.insert(failures, string.format('%s:%s', category, test_name))
  end
end

print(string.format('%s: executed %d, passed %d, failed %d', category, #test_names, passed_count, #failures))

if #failures > 0 then
  error(string.format('%d test(s) failed:\n%s', #failures, table.concat(failures, '\n')), 0)
end
