update public.menu_items
set
  item_type = 'drink',
  menu_period = 'all_day',
  menu_periods = array['all_day']::text[],
  updated_at = timezone('utc', now())
where item_type <> 'drink'
  and (
    lower(coalesce(category, '')) in (
      'kalt',
      'heiss',
      'heiß',
      'mocktail',
      'hausbar',
      'bar',
      'kaffee',
      'tee',
      'softdrink',
      'softdrinks',
      'drink',
      'drinks',
      'getraenk',
      'getränk'
    )
    or lower(coalesce(title, '')) ~ '(espresso|cappuccino|latte|macchiato|mokka|limonade|spritz|spritzer|tonic|cola|fanta|sprite|wasser|saft|schorle|shake|smoothie|cocktail|mocktail|bier|wein|aperol|gin|rum|tee|kaffee|chai|matcha)'
    or lower(coalesce(description, '')) ~ '(espresso|cappuccino|latte|macchiato|limonade|spritz|tonic|cola|wasser|saft|cocktail|mocktail|bier|wein|aperol|gin|rum|tee|kaffee|chai|matcha)'
  );
