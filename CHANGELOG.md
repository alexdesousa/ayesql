# Changelog

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
