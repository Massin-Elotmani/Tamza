import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: () => import('../views/HomeView.vue'),
    },
    {
      path: '/record/',
      name: 'recorder',
      component: () => import('../views/Recorder/RecorderView.vue'),
      children: [
        {
          path: '',
          component: () => import('../views/Recorder/instance/RecorderViewNew.vue'),
        },
        {
          path: ':id',
          component: () => import('../views/Recorder/instance/RecorderViewEdit.vue'),
        },
      ],

    },
  ],
})

export default router
