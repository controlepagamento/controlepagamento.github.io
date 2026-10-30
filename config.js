// Dados do projeto no Supabase (Project Settings → API).
// A "anon public key" pode ficar aqui: ela não dá acesso a nada sozinha —
// quem protege os dados são as regras do banco (schema.sql).
window.MPH_CONFIG = {
  supabaseUrl: 'https://xsvohlmcqruhfkhvuvtf.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhzdm9obG1jcXJ1aGZraHZ1dnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMzNzU0NTUsImV4cCI6MjEwODk1MTQ1NX0.WvfVf0YFwrTlqNo8MYdrzmSsBI-Q2YcTBkv8GpPS8Jc',
  // e-mail do usuário administrador criado no Supabase (ninguém digita: a tela do PIN usa sozinha)
  adminEmail: 'controlepagamentogustavo@gmail.com'
};
