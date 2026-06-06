DROP POLICY "Anyone can join waitlist" ON public.waitlist_signups;

CREATE POLICY "Anyone can join waitlist with valid email"
  ON public.waitlist_signups
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    email IS NOT NULL
    AND length(email) BETWEEN 3 AND 255
    AND email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  );