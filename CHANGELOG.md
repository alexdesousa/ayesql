# Changelog

## v0.5.0

This version maintains the same query language, but it breaks runners as now
queries return `AyeSQL.Query.t()` instead of `{binary(), [term()]}`.

### Enhancements

  * Refactored code to improve readability.
  * Added `AyeSQL.Query` for queries (instead of tuple).
  * Added `AyeSQL.Error` for query errors (instead of returning a string with
    the missing parameter).
  * Added `AyeSQL.AST.Context` to be able to handle several errors, instead of
    returning them one at the time.
  * Improved documentation explaining all features.

## v0.4.1

### Enhancements

  * Added optional arguments for better composition.

## v0.4.0

### Enhancements

  * Added `AyeSQL.Runner` behaviour for writing custom query runners.
  * New query runners for Ecto and Postgrex connections.

## v0.3.2

  * Added configuration support for running queries by default.

## v0.3.1

### Enhancements

  * Added `defqueries/3` to avoid boiler plate code.

## v0.3.0

### Enhancements

  * Simplified lexer and parser.
  * Now it's possible to accept anonymous blocks of code.

## v0.2.0

### Enhancements

  * Now it detects when an SQL file has been changed (suggested by
    [Ole Morten Halvorsen](https://github.com/omh)).
  * Updated dependencies.
  * Improved code for maintainability.
  * Improved tests for more code coverage.
  * Support for Elixir 1.8 and Erlang 21
