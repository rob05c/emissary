defmodule Emissary.CacheControl do
  # \todo downcase keys

  @spec parse(list) :: map
  def parse(headers) do
    case Map.fetch(headers, "cache-control") do
      {:ok, cache_control_str} ->
        parse_str(cache_control_str)
      _ ->
        %{}
    end
  end

  @spec parse_str(String.t) :: map
  defp parse_str(s) do
    parse_key(s, %{})
  end

  @spec next_tok(integer | :nomatch, integer | :nomatch) :: :equal | :comma | :neither
  defp next_tok(equal_pos, comma_pos) do
    cond do
      equal_pos == :nomatch && comma_pos == :nomatch ->
        :neither
      equal_pos == :nomatch && comma_pos != :nomatch ->
        :comma
      equal_pos != :nomatch && comma_pos == :nomatch ->
        :equal
      true ->
        {equal_i, _} = equal_pos
        {comma_i, _} = comma_pos
        if equal_i < comma_i do
          :equal
        else
          :comma
        end
    end
  end

  @spec parse_key(String.t, map) :: map
  defp parse_key(s, acc) do
    s = String.lstrip(s)
    equal_pos = :binary.match s, "="
    comma_pos = :binary.match s, ","
    case next_tok(equal_pos, comma_pos) do
      :neither ->
        s = String.rstrip(s)
        Map.put acc, s, nil
      :equal ->
        {equal_i, _} = equal_pos
        key = String.slice(s, 0, equal_i)
        s = String.slice(s, equal_i+1, byte_size(s))
        parse_val(s, key, acc)
      :comma ->
        {comma_i, _} = comma_pos
        key = String.slice(s, 0, comma_i)
        s = String.slice(s, comma_i+1, byte_size(s))
        acc = Map.put acc, key, nil
        parse_key(s, acc)
    end
  end

  @spec parse_val(String.t, String.t, map) :: map
  defp parse_val(s, key, acc) do
    s = String.lstrip(s)
    if String.at(s, 0) == "\"" do
      parse_quoted_val(s, key, acc)
    else
      parse_unquoted_val(s, key, acc)
    end
  end

  @spec parse_quoted_val(String.t, String.t, map) :: map
  defp parse_quoted_val(s, key, acc) do
    quote_pos = end_quote_pos(s, 1)
    if quote_pos == :nomatch do
        val = String.rstrip(s)
        Map.put acc, key, val
    else
      val = String.slice(s, 1, quote_pos)
      IO.puts "val: '" <> val <> "'"
      acc = Map.put acc, key, val
      s = String.slice(s, quote_pos+1, byte_size(s))
      case :binary.match s, "," do
        :nomatch ->
          acc
        {comma_i, _} ->
          s = String.slice(s, comma_i+1, byte_size(s))
          parse_key s, acc
      end

    end
  end

  @spec end_quote_pos(String.t, integer) :: integer | :nomatch
  defp end_quote_pos(s, start) do
    IO.puts "end_quote_pos s " <> s <> " start " <> Integer.to_string(start)
    s_start = String.slice(s, start, byte_size(s))
    IO.puts "end_quote_pos s_start " <> s_start
    quote_pos = :binary.match s_start, "\""
    if quote_pos == :nomatch do
      IO.puts "end_quote_pos quote_pos :nomatch"
      :nomatch
    else
      {quote_i, _} = quote_pos
      IO.puts "end_quote_pos quote_i " <> Integer.to_string(quote_i)
      if String.at(s_start, quote_i - 1) != "\\" do
        IO.puts "end_quote_pos returning start + quote_i " <> Integer.to_string(start) <> "+" <> Integer.to_string(quote_i)
        start + quote_i - 1
      else
        IO.puts "end_quote_pos recursing start + quote_i + 1 " <> Integer.to_string(start) <> "+" <> Integer.to_string(quote_i) <> "+1"
        end_quote_pos(s, start+quote_i+1)
      end
    end
  end

  @spec parse_unquoted_val(String.t, integer, map) :: map
  defp parse_unquoted_val(s, key, acc) do
    comma_pos = :binary.match s, ","
    case comma_pos do
      {comma_i, _} ->
        val = String.slice(s, 0, comma_i)
        s = String.slice(s, comma_i+1, byte_size(s))
        acc = Map.put acc, key, val
        parse_key s, acc
      :nomatch ->
        val = String.rstrip(s)
        Map.put acc, key, val
    end
  end
end
